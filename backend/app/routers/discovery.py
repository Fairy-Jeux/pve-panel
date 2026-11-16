"""Bonjour / mDNS LAN discovery and onboarding QR/deep-link metadata endpoints."""

from __future__ import annotations

from typing import Any
from urllib.parse import quote

from fastapi import APIRouter, Query, Request

from app.config_manager import get_config_manager
from app.services.mdns_publisher import discover_lan_services, get_primary_lan_ip

router = APIRouter(prefix="/api/discovery", tags=["discovery"])


def _resolve_public_url(request: Request) -> str:
    cfg = get_config_manager().config
    if cfg.server.public_url.strip():
        return cfg.server.public_url.strip().rstrip("/")

    forwarded_host = request.headers.get("x-forwarded-host", "").split(",")[0].strip()
    host = forwarded_host or request.headers.get("host", "").strip()
    if host:
        proto = request.headers.get("x-forwarded-proto", "").split(",")[0].strip().lower()
        if not proto:
            proto = "https" if (".ts.net" in host.lower() or request.url.scheme == "https") else "http"
        return f"{proto}://{host}".rstrip("/")

    lan_ip = get_primary_lan_ip()
    return f"http://{lan_ip}:{cfg.server.listen_port}"


@router.get("/lan")
async def scan_lan_services(
    timeout: float = Query(default=2.0, ge=0.5, le=4.0),
) -> dict[str, Any]:
    """Perform a bounded ~2.0s async mDNS scan for Quick-Add onboarding services."""
    services = await discover_lan_services(timeout=timeout)
    return {"services": services, "count": len(services)}


@router.get("/qr")
async def get_discovery_qr_metadata(request: Request) -> dict[str, Any]:
    """Return deep-link URL and pairing metadata so clients can render crisp QR codes."""
    cfg = get_config_manager().config
    public_url = _resolve_public_url(request)
    server_id = cfg.server.id
    server_name = cfg.server.name

    deep_link = (
        f"pvecenter://connect?url={quote(public_url, safe='')}"
        f"&name={quote(server_name, safe='')}"
        f"&id={quote(server_id, safe='')}"
    )
    onboarding_link = f"{public_url}/?onboarding=1"
    return {
        "deep_link": deep_link,
        "onboarding_link": onboarding_link,
        "public_url": public_url,
        "svg_data_url_or_text": deep_link,
        "server_id": server_id,
        "server_name": server_name,
        "mdns_service_type": cfg.server.mdns_service_type,
        "lan_ip": get_primary_lan_ip(),
        "port": cfg.server.listen_port,
    }
