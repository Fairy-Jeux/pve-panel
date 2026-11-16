"""Asynchronous Proxmox VE API client using restricted API Tokens."""

import asyncio
import os
from pathlib import Path
from typing import Any, Literal

import httpx

from app.config import get_settings, load_storage_mounts_config

HOST_MNT_ROOT = Path(os.environ.get("HOST_MNT_ROOT", "/host_mnt"))


def _resolve_disk_mounts() -> list[dict[str, str]]:
    """Load storage mounts from services.yaml or auto-discover subdirectories under /host_mnt."""
    configured = load_storage_mounts_config()
    if configured:
        return configured
    if not HOST_MNT_ROOT.is_dir():
        return []
    discovered: list[dict[str, str]] = []
    for entry in sorted(HOST_MNT_ROOT.iterdir(), key=lambda p: p.name):
        if entry.is_dir() and entry.name != "pool_medias":
            discovered.append(
                {
                    "mount": f"/mnt/{entry.name}",
                    "subpath": entry.name,
                    "wwn": "",
                    "label": f"Disque {entry.name}",
                }
            )
    return discovered


def _statvfs_usage(path: Path) -> dict[str, Any] | None:
    """Read filesystem byte usage via statvfs when mount exists."""
    if not path.exists():
        return None
    try:
        st = os.statvfs(path)
    except OSError:
        return None
    total_bytes = int(st.f_frsize * st.f_blocks)
    avail_bytes = int(st.f_frsize * st.f_bavail)
    free_bytes = int(st.f_frsize * st.f_bfree)
    used_bytes = max(0, total_bytes - free_bytes)
    usable = used_bytes + avail_bytes
    used_pct = round((used_bytes / usable) * 100, 1) if usable > 0 else 0.0
    return {
        "total_bytes": total_bytes,
        "used_bytes": used_bytes,
        "avail_bytes": avail_bytes,
        "used_pct": used_pct,
    }


def _format_uptime(seconds: int | float) -> str:
    """Format raw uptime seconds into concise French duration."""
    sec = int(seconds or 0)
    days, rem = divmod(sec, 86400)
    hours, rem = divmod(rem, 3600)
    minutes, _ = divmod(rem, 60)
    if days > 0:
        return f"{days}j {hours}h {minutes}m"
    if hours > 0:
        return f"{hours}h {minutes}m"
    return f"{minutes}m"


class ProxmoxClient:
    """Stateless async client for Proxmox VE node & VM/LXC management."""

    def __init__(self, http_client: httpx.AsyncClient) -> None:
        self._http = http_client

    def _headers(self) -> dict[str, str]:
        settings = get_settings()
        return {
            "Authorization": f"PVEAPIToken={settings.pve_token_id}={settings.pve_token_secret}"
        }

    def _base_url(self) -> str:
        settings = get_settings()
        return f"{settings.pve_host.rstrip('/')}/api2/json/nodes/{settings.pve_node}"

    async def get_overview(self) -> dict[str, Any]:
        """Fetch node status, storage pools, LXCs, and VMs concurrently."""
        base = self._base_url()
        headers = self._headers()

        status_req = self._http.get(f"{base}/status", headers=headers)
        storage_req = self._http.get(f"{base}/storage", headers=headers)
        lxc_req = self._http.get(f"{base}/lxc", headers=headers)
        qemu_req = self._http.get(f"{base}/qemu", headers=headers)
        disks_req = self._http.get(f"{base}/disks/list", headers=headers)

        results = await asyncio.gather(
            status_req, storage_req, lxc_req, qemu_req, disks_req, return_exceptions=True
        )

        node_data = self._extract_data(results[0], default={})
        storage_raw = self._extract_data(results[1], default=[])
        lxc_raw = self._extract_data(results[2], default=[])
        qemu_raw = self._extract_data(results[3], default=[])
        disks_raw = self._extract_data(results[4], default=[])

        node_summary = self._build_node_summary(node_data, storage_raw)
        resources = self._build_resources_list(lxc_raw, qemu_raw)
        external_storage = self._build_external_storage(disks_raw)

        running_count = sum(1 for r in resources if r["status"] == "running")
        stopped_count = len(resources) - running_count

        return {
            "online": bool(node_data),
            "node": node_summary,
            "counts": {
                "total": len(resources),
                "running": running_count,
                "stopped": stopped_count,
                "lxc": len(lxc_raw) if isinstance(lxc_raw, list) else 0,
                "qemu": len(qemu_raw) if isinstance(qemu_raw, list) else 0,
            },
            "resources": resources,
            "external_storage": external_storage,
        }

    @staticmethod
    def _build_external_storage(disks_raw: list[dict[str, Any]]) -> dict[str, Any]:
        """Combine MergerFS statvfs mount metrics with Proxmox physical disk SMART info."""
        by_wwn = {
            str(d.get("wwn") or "").lower(): d
            for d in (disks_raw if isinstance(disks_raw, list) else [])
            if isinstance(d, dict) and d.get("wwn")
        }

        pool_stats = _statvfs_usage(HOST_MNT_ROOT / "pool_medias") or {
            "total_bytes": 0,
            "used_bytes": 0,
            "avail_bytes": 0,
            "used_pct": 0.0,
        }
        disk_mounts = _resolve_disk_mounts()
        pool = {
            "name": "Pool Médias (MergerFS)",
            "mount": "/mnt/pool_medias",
            "fstype": "fuse.mergerfs",
            "policy": "mfs (Most Free Space)",
            "drives_count": len(disk_mounts),
            "available": (HOST_MNT_ROOT / "pool_medias").exists(),
            **pool_stats,
        }

        drives = []
        for spec in disk_mounts:
            wwn = str(spec.get("wwn") or "").lower()
            disk_meta = by_wwn.get(wwn, {}) if wwn else {}
            usage = _statvfs_usage(HOST_MNT_ROOT / spec["subpath"]) or {
                "total_bytes": int(disk_meta.get("size") or 0),
                "used_bytes": 0,
                "avail_bytes": 0,
                "used_pct": 0.0,
            }
            drives.append(
                {
                    "mount": spec.get("mount") or f"/mnt/{spec['subpath']}",
                    "label": spec.get("label") or f"Disque {spec['subpath']}",
                    "wwn": spec.get("wwn") or "",
                    "devpath": str(disk_meta.get("devpath") or ""),
                    "model": str(disk_meta.get("model") or "").strip(),
                    "vendor": str(disk_meta.get("vendor") or "").strip(),
                    "serial": str(disk_meta.get("serial") or "").strip(),
                    "type": str(disk_meta.get("type") or "hdd"),
                    "rpm": str(disk_meta.get("rpm") or ""),
                    "health": str(disk_meta.get("health") or "UNKNOWN"),
                    "size_bytes": int(disk_meta.get("size") or usage["total_bytes"]),
                    **usage,
                }
            )

        ssd_meta = None
        if isinstance(disks_raw, list):
            ssd_meta = next(
                (d for d in disks_raw if isinstance(d, dict) and d.get("type") == "ssd"),
                None,
            )
        system_ssd = (
            {
                "devpath": str(ssd_meta.get("devpath") or ""),
                "model": str(ssd_meta.get("model") or "").strip(),
                "serial": str(ssd_meta.get("serial") or "").strip(),
                "health": str(ssd_meta.get("health") or "UNKNOWN"),
                "size_bytes": int(ssd_meta.get("size") or 0),
            }
            if ssd_meta
            else None
        )

        return {
            "pool": pool,
            "drives": drives,
            "system_ssd": system_ssd,
        }

    @staticmethod
    def _extract_data(resp: Any, default: Any) -> Any:
        if isinstance(resp, Exception) or resp.status_code >= 400:
            return default
        try:
            return resp.json().get("data", default)
        except Exception:
            return default

    @staticmethod
    def _build_node_summary(
        node_data: dict[str, Any], storage_raw: list[dict[str, Any]]
    ) -> dict[str, Any]:
        settings = get_settings()
        mem = node_data.get("memory") or {}
        swap = node_data.get("swap") or {}
        rootfs = node_data.get("rootfs") or {}
        cpuinfo = node_data.get("cpuinfo") or {}

        mem_used = int(mem.get("used", 0))
        mem_total = int(mem.get("total", 1)) or 1
        cpu_pct = round(float(node_data.get("cpu", 0.0)) * 100, 1)

        storages = []
        if isinstance(storage_raw, list):
            for st in sorted(storage_raw, key=lambda x: x.get("storage", "")):
                total = int(st.get("total", 0))
                used = int(st.get("used", 0))
                pct = round((used / total) * 100, 1) if total > 0 else 0.0
                storages.append(
                    {
                        "name": st.get("storage", ""),
                        "type": st.get("type", ""),
                        "active": bool(st.get("active", 0)),
                        "used_bytes": used,
                        "total_bytes": total,
                        "used_pct": pct,
                    }
                )

        return {
            "name": settings.pve_node,
            "cpu_pct": cpu_pct,
            "cpu_model": cpuinfo.get("model", "Intel Xeon"),
            "cpu_threads": int(cpuinfo.get("cpus", 0)),
            "loadavg": node_data.get("loadavg", ["0.00", "0.00", "0.00"]),
            "mem_used_bytes": mem_used,
            "mem_total_bytes": mem_total,
            "mem_pct": round((mem_used / mem_total) * 100, 1),
            "swap_used_bytes": int(swap.get("used", 0)),
            "swap_total_bytes": int(swap.get("total", 0)),
            "rootfs_used_bytes": int(rootfs.get("used", 0)),
            "rootfs_total_bytes": int(rootfs.get("total", 0)),
            "uptime_seconds": int(node_data.get("uptime", 0)),
            "uptime_human": _format_uptime(node_data.get("uptime", 0)),
            "pve_version": node_data.get("pveversion", ""),
            "storages": storages,
        }

    @staticmethod
    def _build_resources_list(
        lxc_raw: list[dict[str, Any]], qemu_raw: list[dict[str, Any]]
    ) -> list[dict[str, Any]]:
        settings = get_settings()
        items: list[dict[str, Any]] = []

        for vm_type, raw_list in (("lxc", lxc_raw), ("qemu", qemu_raw)):
            if not isinstance(raw_list, list):
                continue
            for entry in raw_list:
                vmid = int(entry.get("vmid", 0))
                mem = int(entry.get("mem", 0))
                maxmem = int(entry.get("maxmem", 0))
                disk = int(entry.get("disk", 0))
                maxdisk = int(entry.get("maxdisk", 0))
                uptime = int(entry.get("uptime", 0))
                raw_tags = str(entry.get("tags") or "")
                tags = [t.strip() for t in raw_tags.split(";") if t.strip()]

                items.append(
                    {
                        "vmid": vmid,
                        "name": entry.get("name") or f"{vm_type}-{vmid}",
                        "type": vm_type,
                        "status": entry.get("status", "unknown"),
                        "cpu_pct": round(float(entry.get("cpu", 0.0)) * 100, 1),
                        "cpus": int(entry.get("cpus", 1)),
                        "mem_used_bytes": mem,
                        "mem_total_bytes": maxmem,
                        "mem_pct": round((mem / maxmem) * 100, 1) if maxmem > 0 else 0.0,
                        "disk_used_bytes": disk,
                        "disk_total_bytes": maxdisk,
                        "uptime_seconds": uptime,
                        "uptime_human": _format_uptime(uptime) if uptime > 0 else "—",
                        "tags": tags,
                        "is_self": vmid == settings.panel_self_vmid,
                    }
                )

        items.sort(key=lambda x: x["vmid"])
        return items

    async def execute_action(
        self,
        vm_type: Literal["lxc", "qemu"],
        vmid: int,
        action: Literal["start", "stop", "reboot", "shutdown"],
    ) -> dict[str, Any]:
        """Trigger start/stop/reboot/shutdown on a specific LXC or QEMU VM."""
        settings = get_settings()
        if vmid == settings.panel_self_vmid and action in ("stop", "shutdown"):
            raise ValueError(
                f"Protection activée : impossible d'arrêter le conteneur du panel ({vmid})."
            )

        url = f"{self._base_url()}/{vm_type}/{vmid}/status/{action}"
        resp = await self._http.post(url, headers=self._headers())
        if resp.status_code >= 400:
            detail = resp.text[:300]
            raise RuntimeError(f"Erreur Proxmox ({resp.status_code}) : {detail}")

        payload = resp.json()
        return {
            "ok": True,
            "vmid": vmid,
            "type": vm_type,
            "action": action,
            "upid": payload.get("data", ""),
        }
