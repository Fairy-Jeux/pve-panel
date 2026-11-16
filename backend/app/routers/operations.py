"""Live operations center: PVE task history, Jellyseerr requests, qBittorrent controls, and media scans."""

import asyncio
import re
from typing import Any, Literal

import httpx
from fastapi import APIRouter, HTTPException, Request

from app.config import get_settings

router = APIRouter(prefix="/api/ops", tags=["operations"])


def _clean_slug_title(slug: str | None, media_type: str, tmdb_id: Any) -> str:
    """Turn a Jellyseerr externalServiceSlug into a readable title with TMDB fallback."""
    if slug:
        cleaned = re.sub(r"-\d{4}$", "", slug).replace("-", " ").strip()
        if cleaned:
            return cleaned.title()
    label = "Série" if media_type == "tv" else "Film"
    return f"{label} #{tmdb_id}" if tmdb_id else label


async def _qbit_request(
    client: httpx.AsyncClient,
    method: str,
    path: str,
    *,
    params: dict[str, Any] | None = None,
    data: dict[str, Any] | None = None,
) -> httpx.Response:
    """Send an authenticated request to qBittorrent WebUI with cookie login fallback."""
    settings = get_settings()
    if not settings.qbit_url:
        raise HTTPException(status_code=503, detail="qBittorrent non configuré.")

    base = settings.qbit_url.rstrip("/")
    url = f"{base}{path}"
    resp = await client.request(method, url, params=params, data=data, timeout=3.5)
    if resp.status_code in (401, 403) and settings.qbit_username:
        login_resp = await client.post(
            f"{base}/api/v2/auth/login",
            data={
                "username": settings.qbit_username,
                "password": settings.qbit_password,
            },
            headers={"Referer": base},
            timeout=3.5,
        )
        resp = await client.request(
            method,
            url,
            params=params,
            data=data,
            cookies=login_resp.cookies,
            timeout=3.5,
        )
    return resp


async def _fetch_pve_tasks(client: httpx.AsyncClient) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.pve_host or not settings.pve_token_id:
        return []
    url = f"{settings.pve_host.rstrip('/')}/api2/json/nodes/{settings.pve_node}/tasks"
    headers = {
        "Authorization": f"PVEAPIToken={settings.pve_token_id}={settings.pve_token_secret}"
    }
    try:
        resp = await client.get(url, headers=headers, params={"limit": 15}, timeout=4.0)
        if resp.status_code >= 400:
            return []
        raw = resp.json().get("data", [])
        tasks = []
        for item in raw:
            start = int(item.get("starttime") or 0)
            end = int(item.get("endtime") or 0)
            tasks.append(
                {
                    "upid": str(item.get("upid") or ""),
                    "type": str(item.get("type") or "task"),
                    "vmid": str(item.get("id") or ""),
                    "user": str(item.get("user") or ""),
                    "status": str(item.get("status") or ("running" if not end else "OK")),
                    "starttime": start,
                    "endtime": end,
                    "duration_sec": max(0, end - start) if (start and end) else None,
                }
            )
        return tasks
    except Exception:
        return []


async def _fetch_seerr_requests(client: httpx.AsyncClient) -> list[dict[str, Any]]:
    settings = get_settings()
    if not settings.jellyseerr_url or not settings.jellyseerr_api_key:
        return []
    url = f"{settings.jellyseerr_url.rstrip('/')}/api/v1/request"
    headers = {"X-Api-Key": settings.jellyseerr_api_key}
    try:
        resp = await client.get(
            url, headers=headers, params={"take": 12, "sort": "added"}, timeout=4.0
        )
        if resp.status_code >= 400:
            return []
        results = resp.json().get("results", [])
        items = []
        for req in results:
            media = req.get("media") or {}
            req_by = req.get("requestedBy") or {}
            media_type = str(req.get("type") or media.get("mediaType") or "movie")
            title = _clean_slug_title(
                media.get("externalServiceSlug"), media_type, media.get("tmdbId")
            )
            items.append(
                {
                    "id": int(req.get("id", 0)),
                    "status": int(req.get("status", 0)),
                    "media_type": media_type,
                    "title": title,
                    "requested_by": str(
                        req_by.get("displayName")
                        or req_by.get("jellyfinUsername")
                        or "Utilisateur"
                    ),
                    "created_at": str(req.get("createdAt") or ""),
                    "media_status": int(media.get("status", 0)),
                }
            )
        return items
    except Exception:
        return []


async def _fetch_qbit_control(client: httpx.AsyncClient) -> dict[str, Any]:
    settings = get_settings()
    if not settings.qbit_url:
        return {"available": False, "alt_speed_enabled": False, "torrents": []}
    try:
        mode_req = _qbit_request(client, "GET", "/api/v2/transfer/speedLimitsMode")
        torrents_req = _qbit_request(
            client,
            "GET",
            "/api/v2/torrents/info",
            params={"sort": "added_on", "reverse": "true", "limit": 10},
        )
        mode_resp, torrents_resp = await asyncio.gather(mode_req, torrents_req)
        alt_speed = mode_resp.status_code == 200 and mode_resp.text.strip() == "1"
        raw_torrents = torrents_resp.json() if torrents_resp.status_code == 200 else []
        torrents = [
            {
                "hash": str(t.get("hash") or ""),
                "name": str(t.get("name") or "Torrent"),
                "state": str(t.get("state") or "unknown"),
                "progress_pct": round(float(t.get("progress") or 0.0) * 100, 1),
                "dlspeed": int(t.get("dlspeed") or 0),
                "upspeed": int(t.get("upspeed") or 0),
                "size": int(t.get("size") or 0),
                "eta": int(t.get("eta") or 0),
            }
            for t in (raw_torrents if isinstance(raw_torrents, list) else [])
        ]
        return {
            "available": True,
            "alt_speed_enabled": alt_speed,
            "torrents": torrents,
        }
    except Exception:
        return {"available": False, "alt_speed_enabled": False, "torrents": []}


@router.get("/overview")
async def get_ops_overview(request: Request) -> dict[str, Any]:
    """Fetch PVE tasks, Jellyseerr requests, and qBittorrent controls concurrently."""
    pve_http: httpx.AsyncClient = request.app.state.pve_http
    media_http: httpx.AsyncClient = request.app.state.media_http

    pve_tasks, seerr_requests, qbit_control = await asyncio.gather(
        _fetch_pve_tasks(pve_http),
        _fetch_seerr_requests(media_http),
        _fetch_qbit_control(media_http),
    )
    return {
        "pve_tasks": pve_tasks,
        "seerr_requests": seerr_requests,
        "qbit_control": qbit_control,
    }


@router.post("/seerr/{request_id}/{decision}")
async def decide_seerr_request(
    request: Request,
    request_id: int,
    decision: Literal["approve", "decline"],
) -> dict[str, Any]:
    """Approve or decline a pending Jellyseerr media request."""
    settings = get_settings()
    if not settings.jellyseerr_url or not settings.jellyseerr_api_key:
        raise HTTPException(status_code=503, detail="Jellyseerr non configuré.")
    client: httpx.AsyncClient = request.app.state.media_http
    url = f"{settings.jellyseerr_url.rstrip('/')}/api/v1/request/{request_id}/{decision}"
    resp = await client.post(
        url, headers={"X-Api-Key": settings.jellyseerr_api_key}, timeout=5.0
    )
    if resp.status_code >= 400:
        raise HTTPException(
            status_code=502,
            detail=f"Erreur Jellyseerr ({resp.status_code}) : {resp.text[:200]}",
        )
    return {"ok": True, "request_id": request_id, "decision": decision}


@router.post("/qbit/toggle-speed-mode")
async def toggle_qbit_speed_mode(request: Request) -> dict[str, Any]:
    """Toggle qBittorrent alternative speed limits (Turtle Mode)."""
    client: httpx.AsyncClient = request.app.state.media_http
    resp = await _qbit_request(client, "POST", "/api/v2/transfer/toggleSpeedLimitsMode")
    if resp.status_code >= 400:
        raise HTTPException(
            status_code=502, detail=f"Erreur qBittorrent ({resp.status_code})."
        )
    mode_resp = await _qbit_request(client, "GET", "/api/v2/transfer/speedLimitsMode")
    alt_speed = mode_resp.status_code == 200 and mode_resp.text.strip() == "1"
    return {"ok": True, "alt_speed_enabled": alt_speed}


@router.post("/qbit/torrent/{torrent_hash}/{action}")
async def control_qbit_torrent(
    request: Request,
    torrent_hash: str,
    action: Literal["pause", "resume"],
) -> dict[str, Any]:
    """Pause/stop or resume/start a torrent in qBittorrent (supports v4.x and v5.x)."""
    client: httpx.AsyncClient = request.app.state.media_http
    primary_ep = "stop" if action == "pause" else "start"
    fallback_ep = "pause" if action == "pause" else "resume"

    resp = await _qbit_request(
        client, "POST", f"/api/v2/torrents/{primary_ep}", data={"hashes": torrent_hash}
    )
    if resp.status_code == 404:
        resp = await _qbit_request(
            client,
            "POST",
            f"/api/v2/torrents/{fallback_ep}",
            data={"hashes": torrent_hash},
        )
    if resp.status_code >= 400:
        raise HTTPException(
            status_code=502, detail=f"Erreur qBittorrent ({resp.status_code})."
        )
    return {"ok": True, "hash": torrent_hash, "action": action}


@router.post("/media/scan/{target}")
async def trigger_media_scan(
    request: Request,
    target: Literal["jellyfin", "plex"],
) -> dict[str, Any]:
    """Trigger a full library scan on Jellyfin or Plex."""
    settings = get_settings()
    client: httpx.AsyncClient = request.app.state.media_http

    if target == "jellyfin":
        if not settings.jellyfin_url or not settings.jellyfin_api_key:
            raise HTTPException(status_code=503, detail="Jellyfin non configuré.")
        resp = await client.post(
            f"{settings.jellyfin_url.rstrip('/')}/Library/Refresh",
            headers={
                "Authorization": f'MediaBrowser Token="{settings.jellyfin_api_key}"'
            },
            timeout=5.0,
        )
        if resp.status_code >= 400:
            raise HTTPException(
                status_code=502, detail=f"Erreur scan Jellyfin ({resp.status_code})."
            )
        return {"ok": True, "target": "jellyfin"}

    if not settings.plex_url or not settings.plex_token:
        raise HTTPException(status_code=503, detail="Plex non configuré.")
    base = settings.plex_url.rstrip("/")
    params = {"X-Plex-Token": settings.plex_token}
    sections_resp = await client.get(
        f"{base}/library/sections",
        params=params,
        headers={"Accept": "application/json"},
        timeout=4.0,
    )
    if sections_resp.status_code >= 400:
        raise HTTPException(
            status_code=502, detail=f"Erreur scan Plex ({sections_resp.status_code})."
        )
    dirs = sections_resp.json().get("MediaContainer", {}).get("Directory", [])
    keys = [d.get("key") for d in dirs if d.get("key")]
    await asyncio.gather(
        *[
            client.get(f"{base}/library/sections/{k}/refresh", params=params, timeout=4.0)
            for k in keys
        ],
        return_exceptions=True,
    )
    return {"ok": True, "target": "plex", "sections_scanned": len(keys)}
