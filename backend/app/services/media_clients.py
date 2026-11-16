"""Asynchronous clients for healthchecks and media/download service widgets."""

import asyncio
from datetime import datetime, timedelta, timezone
import time
from typing import Any
import xml.etree.ElementTree as ET

import httpx

from app.config import get_settings


async def check_single_service(
    client: httpx.AsyncClient, service: dict[str, Any]
) -> dict[str, Any]:
    """Perform non-blocking HTTP healthcheck on a declared service."""
    ping_url = service.get("ping_url") or service.get("url") or ""
    if not ping_url:
        return {**service, "online": False, "latency_ms": None, "status_code": None}

    start = time.perf_counter()
    try:
        resp = await client.get(ping_url, follow_redirects=True, timeout=2.5)
        latency_ms = int((time.perf_counter() - start) * 1000)
        online = resp.status_code < 500
        return {
            **service,
            "online": online,
            "latency_ms": latency_ms,
            "status_code": resp.status_code,
        }
    except Exception:
        return {
            **service,
            "online": False,
            "latency_ms": None,
            "status_code": None,
        }


async def check_categories_health(
    client: httpx.AsyncClient, categories: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    """Run healthchecks concurrently across all categories and services."""
    tasks = []
    index_map: list[tuple[int, int]] = []

    result_categories: list[dict[str, Any]] = []
    for cat_idx, cat in enumerate(categories):
        services_list = cat.get("services") or []
        result_categories.append(
            {"name": cat.get("name", "Services"), "services": [None] * len(services_list)}
        )
        for svc_idx, svc in enumerate(services_list):
            tasks.append(check_single_service(client, svc))
            index_map.append((cat_idx, svc_idx))

    checked = await asyncio.gather(*tasks)
    for (cat_idx, svc_idx), svc_result in zip(index_map, checked):
        result_categories[cat_idx]["services"][svc_idx] = svc_result

    return result_categories


async def fetch_jellyfin_widget(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch active playback streams and library item counts from Jellyfin."""
    settings = get_settings()
    if not settings.jellyfin_url or not settings.jellyfin_api_key:
        return {"status": "unconfigured"}

    base = settings.jellyfin_url.rstrip("/")
    headers = {"Authorization": f'MediaBrowser Token="{settings.jellyfin_api_key}"'}

    try:
        sessions_req = client.get(f"{base}/Sessions", headers=headers, timeout=2.5)
        counts_req = client.get(f"{base}/Items/Counts", headers=headers, timeout=2.5)
        sessions_resp, counts_resp = await asyncio.gather(sessions_req, counts_req)

        active_streams = []
        if sessions_resp.status_code == 200:
            for s in sessions_resp.json():
                now_playing = s.get("NowPlayingItem")
                if not now_playing:
                    continue
                play_state = s.get("PlayState") or {}
                series_name = now_playing.get("SeriesName")
                item_name = now_playing.get("Name", "Média")
                title = f"{series_name} — {item_name}" if series_name else item_name
                active_streams.append(
                    {
                        "user": s.get("UserName", "Utilisateur"),
                        "title": title,
                        "device": s.get("DeviceName", "Client"),
                        "play_method": play_state.get("PlayMethod", "DirectPlay"),
                        "is_paused": bool(play_state.get("IsPaused", False)),
                    }
                )

        counts = counts_resp.json() if counts_resp.status_code == 200 else {}
        return {
            "status": "ok",
            "active_streams_count": len(active_streams),
            "active_streams": active_streams[:4],
            "movies_count": int(counts.get("MovieCount", 0)),
            "series_count": int(counts.get("SeriesCount", 0)),
            "episodes_count": int(counts.get("EpisodeCount", 0)),
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)[:120]}


async def fetch_plex_widget(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch active sessions and library sections from Plex Media Server."""
    settings = get_settings()
    if not settings.plex_url or not settings.plex_token:
        return {"status": "unconfigured"}

    base = settings.plex_url.rstrip("/")
    params = {"X-Plex-Token": settings.plex_token}
    headers = {"Accept": "application/json"}

    try:
        sessions_req = client.get(
            f"{base}/status/sessions", params=params, headers=headers, timeout=2.5
        )
        sections_req = client.get(
            f"{base}/library/sections", params=params, headers=headers, timeout=2.5
        )
        id_req = client.get(f"{base}/identity", timeout=2.5)
        sessions_resp, sections_resp, id_resp = await asyncio.gather(
            sessions_req, sections_req, id_req, return_exceptions=True
        )

        active_streams = 0
        if not isinstance(sessions_resp, Exception) and sessions_resp.status_code == 200:
            data = sessions_resp.json().get("MediaContainer", {})
            active_streams = int(data.get("size", 0))

        libraries = []
        if not isinstance(sections_resp, Exception) and sections_resp.status_code == 200:
            dirs = sections_resp.json().get("MediaContainer", {}).get("Directory", [])
            libraries = [d.get("title", "") for d in dirs if d.get("title")]

        version = ""
        if not isinstance(id_resp, Exception) and id_resp.status_code == 200:
            text = id_resp.text
            if text.lstrip().startswith("<"):
                root = ET.fromstring(text)
                version = root.attrib.get("version", "").split("-")[0]

        return {
            "status": "ok",
            "active_streams_count": active_streams,
            "libraries_count": len(libraries),
            "libraries": libraries[:4],
            "version": version,
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)[:120]}


async def fetch_radarr_widget(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch movies stats, queue count, and upcoming releases from Radarr."""
    settings = get_settings()
    if not settings.radarr_url or not settings.radarr_api_key:
        return {"status": "unconfigured"}

    base = f"{settings.radarr_url.rstrip('/')}/api/v3"
    headers = {"X-Api-Key": settings.radarr_api_key}
    now = datetime.now(timezone.utc)
    end = now + timedelta(days=30)
    cal_params = {
        "start": now.strftime("%Y-%m-%d"),
        "end": end.strftime("%Y-%m-%d"),
    }

    try:
        movies_req = client.get(f"{base}/movie", headers=headers, timeout=3.0)
        queue_req = client.get(f"{base}/queue", headers=headers, timeout=2.5)
        cal_req = client.get(
            f"{base}/calendar", headers=headers, params=cal_params, timeout=2.5
        )
        movies_resp, queue_resp, cal_resp = await asyncio.gather(
            movies_req, queue_req, cal_req
        )

        movies = movies_resp.json() if movies_resp.status_code == 200 else []
        downloaded = sum(1 for m in movies if m.get("hasFile"))
        missing = sum(
            1 for m in movies if m.get("monitored") and not m.get("hasFile")
        )

        queue_data = queue_resp.json() if queue_resp.status_code == 200 else {}
        queue_count = int(queue_data.get("totalRecords", 0))

        upcoming = []
        if cal_resp.status_code == 200:
            for item in cal_resp.json()[:3]:
                upcoming.append(
                    {
                        "title": item.get("title", "Film"),
                        "date": (
                            item.get("digitalRelease")
                            or item.get("physicalRelease")
                            or item.get("inCinemas")
                            or ""
                        )[:10],
                    }
                )

        return {
            "status": "ok",
            "movies_total": len(movies),
            "movies_downloaded": downloaded,
            "movies_missing": missing,
            "queue_count": queue_count,
            "upcoming": upcoming,
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)[:120]}


async def fetch_sonarr_widget(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch series stats, queue count, and upcoming episodes from Sonarr."""
    settings = get_settings()
    if not settings.sonarr_url or not settings.sonarr_api_key:
        return {"status": "unconfigured"}

    base = f"{settings.sonarr_url.rstrip('/')}/api/v3"
    headers = {"X-Api-Key": settings.sonarr_api_key}
    now = datetime.now(timezone.utc)
    end = now + timedelta(days=7)
    cal_params = {
        "start": now.strftime("%Y-%m-%d"),
        "end": end.strftime("%Y-%m-%d"),
        "includeSeries": "true",
    }

    try:
        series_req = client.get(f"{base}/series", headers=headers, timeout=3.0)
        queue_req = client.get(f"{base}/queue", headers=headers, timeout=2.5)
        cal_req = client.get(
            f"{base}/calendar", headers=headers, params=cal_params, timeout=2.5
        )
        series_resp, queue_resp, cal_resp = await asyncio.gather(
            series_req, queue_req, cal_req
        )

        series_list = series_resp.json() if series_resp.status_code == 200 else []
        episodes_total = sum(
            int((s.get("statistics") or {}).get("episodeFileCount", 0))
            for s in series_list
        )

        queue_data = queue_resp.json() if queue_resp.status_code == 200 else {}
        queue_count = int(queue_data.get("totalRecords", 0))

        upcoming = []
        if cal_resp.status_code == 200:
            for ep in cal_resp.json()[:3]:
                series_title = (ep.get("series") or {}).get("title") or ep.get(
                    "title", "Série"
                )
                s_num = int(ep.get("seasonNumber", 0))
                e_num = int(ep.get("episodeNumber", 0))
                upcoming.append(
                    {
                        "title": f"{series_title} S{s_num:02d}E{e_num:02d}",
                        "date": (ep.get("airDateUtc") or ep.get("airDate") or "")[:10],
                    }
                )

        return {
            "status": "ok",
            "series_total": len(series_list),
            "episodes_downloaded": episodes_total,
            "queue_count": queue_count,
            "upcoming": upcoming,
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)[:120]}


async def fetch_prowlarr_widget(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch indexer count and query/grab statistics from Prowlarr."""
    settings = get_settings()
    if not settings.prowlarr_url or not settings.prowlarr_api_key:
        return {"status": "unconfigured"}

    base = f"{settings.prowlarr_url.rstrip('/')}/api/v1"
    headers = {"X-Api-Key": settings.prowlarr_api_key}

    try:
        idx_req = client.get(f"{base}/indexer", headers=headers, timeout=2.5)
        stats_req = client.get(f"{base}/indexerstats", headers=headers, timeout=2.5)
        idx_resp, stats_resp = await asyncio.gather(idx_req, stats_req)

        indexers = idx_resp.json() if idx_resp.status_code == 200 else []
        enabled_indexers = sum(1 for i in indexers if i.get("enable"))

        queries = 0
        grabs = 0
        if stats_resp.status_code == 200:
            for item in stats_resp.json().get("indexers", []):
                queries += int(item.get("numberOfQueries", 0))
                grabs += int(item.get("numberOfGrabs", 0))

        return {
            "status": "ok",
            "indexers_enabled": enabled_indexers,
            "indexers_total": len(indexers),
            "queries": queries,
            "grabs": grabs,
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)[:120]}


async def fetch_qbittorrent_widget(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch real-time download/upload speeds and active torrent counts from qBittorrent."""
    settings = get_settings()
    if not settings.qbit_url:
        return {"status": "unconfigured"}

    base = settings.qbit_url.rstrip("/")
    try:
        transfer_resp = await client.get(f"{base}/api/v2/transfer/info", timeout=2.5)
        cookies = None
        if transfer_resp.status_code in (401, 403) and settings.qbit_username:
            login_resp = await client.post(
                f"{base}/api/v2/auth/login",
                data={
                    "username": settings.qbit_username,
                    "password": settings.qbit_password,
                },
                headers={"Referer": base},
                timeout=2.5,
            )
            cookies = login_resp.cookies
            transfer_resp = await client.get(
                f"{base}/api/v2/transfer/info", cookies=cookies, timeout=2.5
            )

        torrents_resp = await client.get(
            f"{base}/api/v2/torrents/info", cookies=cookies, timeout=2.5
        )

        transfer = transfer_resp.json() if transfer_resp.status_code == 200 else {}
        torrents = torrents_resp.json() if torrents_resp.status_code == 200 else []

        downloading = sum(
            1
            for t in torrents
            if str(t.get("state", "")).startswith(("downloading", "metaDL", "stalledDL"))
        )
        seeding = sum(
            1
            for t in torrents
            if str(t.get("state", "")).startswith(("uploading", "stalledUP", "forcedUP"))
        )

        return {
            "status": "ok",
            "dl_speed_bytes": int(transfer.get("dl_info_speed", 0)),
            "up_speed_bytes": int(transfer.get("up_info_speed", 0)),
            "dl_total_bytes": int(transfer.get("dl_info_data", 0)),
            "up_total_bytes": int(transfer.get("up_info_data", 0)),
            "downloading_count": downloading,
            "seeding_count": seeding,
            "torrents_total": len(torrents),
        }
    except Exception as exc:
        return {"status": "error", "error": str(exc)[:120]}


async def fetch_all_widgets(client: httpx.AsyncClient) -> dict[str, Any]:
    """Fetch all service widgets concurrently in a single parallel batch."""
    results = await asyncio.gather(
        fetch_jellyfin_widget(client),
        fetch_plex_widget(client),
        fetch_radarr_widget(client),
        fetch_sonarr_widget(client),
        fetch_prowlarr_widget(client),
        fetch_qbittorrent_widget(client),
    )
    return {
        "jellyfin": results[0],
        "plex": results[1],
        "radarr": results[2],
        "sonarr": results[3],
        "prowlarr": results[4],
        "qbittorrent": results[5],
    }
