"""Declarative config.yaml editor/validation/export, onboarding init, health, and SSE/WS realtime stream."""

from __future__ import annotations

import asyncio
import json
import secrets
from typing import Any
from uuid import uuid4

import anyio
import httpx
from fastapi import APIRouter, HTTPException, Request, WebSocket, WebSocketDisconnect
from fastapi.responses import JSONResponse, Response, StreamingResponse
from pydantic import BaseModel, Field

from app.config import is_configured
from app.config_manager import get_config_manager, hash_pin, hash_token
from app.config_schema import ApiTokenConfig, AppConfig, is_masked_or_empty, utc_now_iso
from app.services.realtime_bus import get_realtime_bus

router = APIRouter(prefix="/api", tags=["config"])

WS_PING_INTERVAL_SECONDS = 25.0
SSE_KEEPALIVE_SECONDS = 25.0


class YamlPayload(BaseModel):
    """Raw YAML payload for validation or persistence."""

    yaml: str = Field(..., min_length=1)


class OnboardingInitPayload(BaseModel):
    """Initial onboarding payload generating config.yaml + first admin API token."""

    server_name: str = "PVE Command Center"
    public_url: str = ""
    listen_host: str | None = None
    listen_port: int | None = Field(default=None, ge=1, le=65535)
    mdns_enabled: bool = True
    tailscale_sso_enabled: bool = True
    allowed_tailscale_users: list[str] | str = Field(default_factory=list)
    dev_auth_bypass: bool = False
    admin_pin: str = ""
    token_name: str = "Initial Admin Token"
    proxmox: dict[str, Any] | None = None
    integrations: dict[str, Any] | None = None
    alerts: dict[str, Any] | None = None
    notifications: dict[str, Any] | None = None
    categories: list[dict[str, Any]] | None = None
    custom_services: list[dict[str, Any]] | None = None
    storage_mounts: list[dict[str, Any]] | None = None


def _require_admin(request: Request) -> dict[str, Any]:
    user = getattr(request.state, "user", None)
    if not isinstance(user, dict):
        raise HTTPException(status_code=401, detail="Authentification requise.")
    if user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Droits administrateur requis.")
    return user


def _build_parsed_summary(cfg: AppConfig) -> dict[str, Any]:
    return {
        "version": cfg.version,
        "server_id": cfg.server.id,
        "server_name": cfg.server.name,
        "listen_port": cfg.server.listen_port,
        "public_url": cfg.server.public_url,
        "proxmox_host": cfg.proxmox.host,
        "proxmox_node": cfg.proxmox.default_node,
        "categories_count": len(cfg.categories),
        "custom_services_count": len(cfg.custom_services),
        "webhooks_count": len(cfg.notifications.webhooks),
        "api_tokens_count": len(cfg.security.api_tokens),
        "alerts_enabled": cfg.alerts.enabled,
        "apns_enabled": cfg.notifications.apns.enabled,
    }


def _sync_pve_http_client(app: Any, old_verify_ssl: bool, new_verify_ssl: bool) -> None:
    if old_verify_ssl == new_verify_ssl:
        return
    old_client = getattr(app.state, "pve_http", None)
    app.state.pve_http = httpx.AsyncClient(
        verify=new_verify_ssl,
        timeout=httpx.Timeout(5.0, connect=3.0),
    )
    if old_client is not None:
        asyncio.create_task(_close_client_quietly(old_client))


async def _close_client_quietly(client: httpx.AsyncClient) -> None:
    try:
        await client.aclose()
    except Exception:
        pass


@router.get("/health")
async def healthcheck() -> dict[str, Any]:
    """Public lightweight healthcheck returning server identity and configuration state."""
    manager = get_config_manager()
    cfg = manager.config
    return {
        "status": "ok",
        "version": "1.0.0",
        "server_id": cfg.server.id,
        "server_name": cfg.server.name,
        "is_configured": is_configured(),
        "config_hash": manager.content_hash[:12],
    }


@router.get("/events/stream")
async def stream_realtime_events(request: Request) -> StreamingResponse:
    """Server-Sent Events stream broadcasting real-time snake_case events."""
    bus = get_realtime_bus()

    async def event_generator():
        yield ": connected\n\n"
        try:
            async with bus.subscribe() as queue:
                while True:
                    if await request.is_disconnected():
                        break
                    try:
                        event = await asyncio.wait_for(
                            queue.get(), timeout=SSE_KEEPALIVE_SECONDS
                        )
                    except asyncio.TimeoutError:
                        yield ": keepalive\n\n"
                        continue
                    if event is None:
                        break
                    yield f"data: {json.dumps(event, separators=(',', ':'))}\n\n"
        except asyncio.CancelledError:
            return

    return StreamingResponse(
        event_generator(),
        media_type="text/event-stream",
        headers={
            "Cache-Control": "no-cache",
            "Connection": "keep-alive",
            "X-Accel-Buffering": "no",
        },
    )


@router.websocket("/ws/events")
async def websocket_realtime_events(websocket: WebSocket) -> None:
    """WebSocket stream sending 25s pings, accepting pongs, and broadcasting events."""
    user = getattr(websocket.state, "user", None)
    if not isinstance(user, dict):
        await websocket.close(code=4401, reason="Authentification requise.")
        return

    await websocket.accept()
    bus = get_realtime_bus()

    async with bus.subscribe() as queue:
        async def _receiver(cancel_scope: anyio.CancelScope) -> None:
            try:
                while True:
                    raw_msg = await websocket.receive_text()
                    text = raw_msg.strip().lower()
                    if text == "pong":
                        continue
                    try:
                        parsed = json.loads(raw_msg)
                        if isinstance(parsed, dict) and parsed.get("type") == "pong":
                            continue
                    except Exception:
                        pass
            except WebSocketDisconnect:
                cancel_scope.cancel()

        async def _sender(cancel_scope: anyio.CancelScope) -> None:
            try:
                while True:
                    try:
                        event = await asyncio.wait_for(
                            queue.get(), timeout=WS_PING_INTERVAL_SECONDS
                        )
                    except asyncio.TimeoutError:
                        await websocket.send_json(bus.build_event("ping", {}))
                        continue
                    if event is None:
                        cancel_scope.cancel()
                        break
                    await websocket.send_json(event)
            except WebSocketDisconnect:
                cancel_scope.cancel()

        async with anyio.create_task_group() as tg:
            tg.start_soon(_receiver, tg.cancel_scope)
            tg.start_soon(_sender, tg.cancel_scope)


@router.get("/config/yaml")
async def get_config_yaml(request: Request) -> dict[str, Any]:
    """Return declarative config.yaml text (literal secrets masked, ${VAR} kept), hash, and summary."""
    _require_admin(request)
    manager = get_config_manager()
    cfg = manager.config
    return {
        "yaml": manager.raw_yaml_text(mask_secrets=True),
        "hash": manager.content_hash,
        "is_synthesized": manager.is_synthesized,
        "config_exists": manager.config_exists,
        "secrets_masked": True,
        "parsed_summary": _build_parsed_summary(cfg),
    }


@router.post("/config/validate")
async def validate_config_yaml(
    request: Request, payload: YamlPayload
) -> dict[str, Any]:
    """Validate candidate config.yaml without saving to disk."""
    _require_admin(request)
    manager = get_config_manager()
    valid, errors, warnings, parsed_cfg = manager.validate_yaml(payload.yaml)
    return {
        "valid": valid,
        "errors": errors,
        "warnings": warnings,
        "parsed_summary": _build_parsed_summary(parsed_cfg) if parsed_cfg else None,
    }


@router.put("/config/yaml")
async def update_config_yaml(
    request: Request, payload: YamlPayload
) -> Response:
    """Validate, atomically persist, and hot-reload declarative config.yaml."""
    _require_admin(request)
    manager = get_config_manager()
    old_verify_ssl = manager.config.proxmox.verify_ssl

    valid, errors, warnings, _ = manager.validate_yaml(payload.yaml)
    if not valid:
        return JSONResponse(
            status_code=422,
            content={
                "ok": False,
                "valid": False,
                "errors": errors,
                "warnings": warnings,
                "detail": "; ".join(errors),
            },
        )

    try:
        new_cfg, final_warnings = manager.save_raw_yaml(
            payload.yaml, emit_event=True, source="yaml_put"
        )
    except ValueError as exc:
        return JSONResponse(
            status_code=422,
            content={
                "ok": False,
                "valid": False,
                "errors": [str(exc)],
                "warnings": warnings,
                "detail": str(exc),
            },
        )

    _sync_pve_http_client(request.app, old_verify_ssl, new_cfg.proxmox.verify_ssl)
    return JSONResponse(
        status_code=200,
        content={
            "ok": True,
            "valid": True,
            "hash": manager.content_hash,
            "warnings": final_warnings,
            "parsed_summary": _build_parsed_summary(new_cfg),
            "message": "Configuration YAML enregistrée et rechargée à chaud.",
        },
    )


@router.get("/config/export")
async def export_config_yaml(request: Request) -> Response:
    """Download masked config.yaml snapshot."""
    _require_admin(request)
    manager = get_config_manager()
    yaml_text = manager.raw_yaml_text(mask_secrets=True)
    return Response(
        content=yaml_text,
        media_type="application/x-yaml",
        headers={"Content-Disposition": 'attachment; filename="config.yaml"'},
    )


@router.get("/onboarding/status")
async def get_onboarding_status() -> dict[str, Any]:
    """Return non-secret onboarding and authentication capability status."""
    manager = get_config_manager()
    cfg = manager.config
    configured = is_configured()
    auth_methods: list[str] = ["api_token"]
    if cfg.security.tailscale_sso_enabled:
        auth_methods.insert(0, "tailscale_sso")
    if cfg.security.admin_pin_hash:
        auth_methods.append("pin")

    return {
        "is_configured": configured,
        "needs_onboarding": not configured,
        "config_exists": manager.config_exists,
        "is_synthesized": manager.is_synthesized,
        "server_id": cfg.server.id,
        "server_name": cfg.server.name,
        "public_url": cfg.server.public_url,
        "tailscale_sso_enabled": cfg.security.tailscale_sso_enabled,
        "pin_configured": bool(cfg.security.admin_pin_hash),
        "api_tokens_count": len(cfg.security.api_tokens),
        "auth_methods": auth_methods,
    }


@router.post("/onboarding/init")
async def init_onboarding(
    request: Request, payload: OnboardingInitPayload
) -> dict[str, Any]:
    """Initialize config.yaml and mint the first admin API token (public only before initial setup)."""
    configured = is_configured()
    if configured:
        user = getattr(request.state, "user", None)
        if not isinstance(user, dict):
            raise HTTPException(status_code=401, detail="Authentification requise.")
        if user.get("role") != "admin":
            raise HTTPException(
                status_code=403,
                detail="Seul un administrateur peut ré-exécuter l'onboarding.",
            )

    manager = get_config_manager()
    old_verify_ssl = manager.config.proxmox.verify_ssl
    base_dict = manager.config.model_dump()

    # Server
    server = dict(base_dict.get("server") or {})
    server["name"] = payload.server_name.strip() or "PVE Command Center"
    server["mdns_service_name"] = server["name"]
    server["public_url"] = payload.public_url.strip()
    server["mdns_enabled"] = payload.mdns_enabled
    if payload.listen_host is not None:
        server["listen_host"] = payload.listen_host.strip()
    if payload.listen_port is not None:
        server["listen_port"] = payload.listen_port
    base_dict["server"] = server

    # Security
    security = dict(base_dict.get("security") or {})
    security["tailscale_sso_enabled"] = payload.tailscale_sso_enabled
    security["allowed_tailscale_users"] = payload.allowed_tailscale_users
    security["dev_auth_bypass"] = payload.dev_auth_bypass
    if not str(security.get("session_secret") or "").strip():
        security["session_secret"] = secrets.token_hex(32)

    raw_pin = payload.admin_pin.strip()
    if raw_pin:
        if len(raw_pin) < 4:
            raise HTTPException(
                status_code=422,
                detail="Le code PIN administrateur doit contenir au moins 4 caractères.",
            )
        security["admin_pin_hash"] = hash_pin(raw_pin)

    plaintext_token = f"pve_{secrets.token_urlsafe(32)}"
    token_entry = ApiTokenConfig(
        id=str(uuid4()),
        name=payload.token_name.strip() or "Initial Admin Token",
        token_hash=hash_token(plaintext_token),
        role="admin",
        created_at=utc_now_iso(),
    )
    existing_tokens = list(security.get("api_tokens") or [])
    existing_tokens.append(token_entry.model_dump())
    security["api_tokens"] = existing_tokens
    base_dict["security"] = security

    # Optional sections
    if payload.proxmox is not None:
        pve = dict(base_dict.get("proxmox") or {})
        for k, v in payload.proxmox.items():
            if k == "token_secret" and is_masked_or_empty(v):
                continue
            pve[k] = v
        base_dict["proxmox"] = pve

    if payload.integrations is not None:
        integ = dict(base_dict.get("integrations") or {})
        for svc_key, svc_val in payload.integrations.items():
            if isinstance(svc_val, dict) and isinstance(integ.get(svc_key), dict):
                merged_svc = dict(integ[svc_key])
                for fk, fv in svc_val.items():
                    if fk in ("api_key", "token", "password") and is_masked_or_empty(fv):
                        continue
                    merged_svc[fk] = fv
                integ[svc_key] = merged_svc
        base_dict["integrations"] = integ

    if payload.alerts is not None:
        alerts = dict(base_dict.get("alerts") or {})
        alerts.update(payload.alerts)
        base_dict["alerts"] = alerts

    if payload.notifications is not None:
        base_dict["notifications"] = payload.notifications

    if payload.categories is not None:
        base_dict["categories"] = payload.categories

    if payload.custom_services is not None:
        base_dict["custom_services"] = payload.custom_services

    if payload.storage_mounts is not None:
        base_dict["storage_mounts"] = payload.storage_mounts

    try:
        validated = AppConfig.model_validate(base_dict)
    except Exception as exc:
        raise HTTPException(status_code=422, detail=f"Configuration invalide : {exc}") from exc

    saved_cfg = manager.save_config(
        validated, preserve_templates=True, emit_event=True, source="onboarding_init"
    )
    _sync_pve_http_client(request.app, old_verify_ssl, saved_cfg.proxmox.verify_ssl)

    return {
        "ok": True,
        "is_configured": is_configured(),
        "server_id": saved_cfg.server.id,
        "server_name": saved_cfg.server.name,
        "api_token": plaintext_token,
        "token_id": token_entry.id,
        "config_hash": manager.content_hash,
        "config_path": str(manager.config_path),
    }
