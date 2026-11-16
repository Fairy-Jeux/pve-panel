"""APNs device token registration and multi-channel notification management endpoints."""

from __future__ import annotations

from pathlib import Path
from typing import Any, Literal
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field

from app.config_manager import get_config_manager
from app.config_schema import (
    MASKED_SECRET_SENTINEL,
    APNsConfig,
    NotificationsConfig,
    WebhookChannelConfig,
    WebhookType,
    is_masked_or_empty,
    is_secret_configured,
)
from app.services.notifications import NotificationDispatcher, NotificationEvent
from app.services.state_store import StateStore, utc_now_iso

router = APIRouter(prefix="/api/notifications", tags=["notifications"])

_SENSITIVE_HEADER_TOKENS = ("auth", "token", "secret", "key", "password")


def _require_state_store(request: Request) -> StateStore:
    store = getattr(request.app.state, "state_store", None)
    if store is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="StateStore non initialisé",
        )
    return store


def _mask_headers(headers: dict[str, str]) -> tuple[dict[str, str], bool]:
    masked: dict[str, str] = {}
    has_secret = False
    for key, val in headers.items():
        if any(tok in key.lower() for tok in _SENSITIVE_HEADER_TOKENS) and is_secret_configured(val):
            masked[key] = MASKED_SECRET_SENTINEL
            has_secret = True
        else:
            masked[key] = val
    return masked, has_secret


def _serialize_channels_summary(
    cfg: NotificationsConfig, devices: list[dict[str, Any]]
) -> dict[str, Any]:
    apns = cfg.apns
    key_exists = bool(apns.private_key_path and Path(apns.private_key_path).is_file())
    apns_summary = {
        "enabled": apns.enabled,
        "team_id": apns.team_id,
        "key_id": apns.key_id,
        "bundle_id": apns.bundle_id,
        "private_key_path": apns.private_key_path,
        "private_key_exists": key_exists,
        "use_sandbox": apns.use_sandbox,
        "configured": bool(apns.team_id and apns.key_id and key_exists),
        "registered_devices_count": len(devices),
        "devices": devices,
    }

    webhooks_summary: list[dict[str, Any]] = []
    for wh in cfg.webhooks:
        has_bot_token = is_secret_configured(wh.bot_token)
        masked_headers, has_secret_headers = _mask_headers(wh.headers)
        webhooks_summary.append(
            {
                "id": wh.id,
                "name": wh.name,
                "type": wh.type,
                "enabled": wh.enabled,
                "url": wh.url,
                "bot_token": MASKED_SECRET_SENTINEL if has_bot_token else "",
                "bot_token_set": has_bot_token,
                "chat_id": wh.chat_id,
                "headers": masked_headers,
                "has_secret_headers": has_secret_headers,
                "notify_on_down": wh.notify_on_down,
                "notify_on_recovery": wh.notify_on_recovery,
                "include_details": wh.include_details,
            }
        )

    return {"apns": apns_summary, "webhooks": webhooks_summary}


class RegisterAPNsDevicePayload(BaseModel):
    """Payload sent by iOS/tvOS/macOS app to register an APNs push token."""

    model_config = ConfigDict(extra="ignore")

    device_token: str = Field(..., min_length=16, max_length=512)
    platform: Literal["ios", "ipados", "tvos", "macos"] = "ios"
    device_name: str = ""
    app_version: str = ""
    environment: Literal["sandbox", "production"] = "production"


class APNsUpdatePayload(BaseModel):
    """Update APNs configuration fields."""

    model_config = ConfigDict(extra="ignore")

    enabled: bool | None = None
    team_id: str | None = None
    key_id: str | None = None
    bundle_id: str | None = None
    private_key_path: str | None = None
    use_sandbox: bool | None = None


class WebhookUpdatePayload(BaseModel):
    """Create or update a notification webhook channel without leaking/erasing secrets."""

    model_config = ConfigDict(extra="ignore")

    id: str = ""
    name: str = Field(..., min_length=1)
    type: WebhookType
    enabled: bool = True
    url: str = ""
    bot_token: str | None = None
    chat_id: str = ""
    headers: dict[str, str] = Field(default_factory=dict)
    notify_on_down: bool = True
    notify_on_recovery: bool = True
    include_details: bool = True


class UpdateNotificationChannelsPayload(BaseModel):
    """Update APNs and/or webhook channels in config.yaml."""

    model_config = ConfigDict(extra="ignore")

    apns: APNsUpdatePayload | None = None
    webhooks: list[WebhookUpdatePayload] | None = None


class TestNotificationPayload(BaseModel):
    """Request payload for sending a live test notification."""

    model_config = ConfigDict(extra="ignore")

    channel_id: str | None = None
    channel_type: Literal["apns", "discord", "telegram", "generic", "all"] = "all"
    title: str | None = None
    message: str | None = None


@router.post("/devices")
async def register_apns_device(
    request: Request, payload: RegisterAPNsDevicePayload
) -> dict[str, Any]:
    """Register or update an APNs device token in SQLite StateStore."""
    store = _require_state_store(request)
    clean_token = payload.device_token.strip().replace(" ", "")
    if not clean_token:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="device_token invalide",
        )
    device = await store.upsert_apns_device(
        device_token=clean_token,
        platform=payload.platform,
        device_name=payload.device_name,
        app_version=payload.app_version,
        environment=payload.environment,
    )
    return {"ok": True, "device": device}


@router.delete("/devices/{token}")
async def unregister_apns_device(request: Request, token: str) -> dict[str, Any]:
    """Unregister an APNs device token."""
    store = _require_state_store(request)
    deleted = await store.delete_apns_device(token)
    return {
        "ok": True,
        "deleted": deleted,
        "device_token": token.strip().replace(" ", "").lower(),
    }


@router.get("/channels")
async def get_notification_channels(request: Request) -> dict[str, Any]:
    """Return APNs status and webhook channels with secrets masked."""
    cfg = get_config_manager().config
    store = _require_state_store(request)
    devices = await store.list_apns_devices()
    return _serialize_channels_summary(cfg.notifications, devices)


@router.put("/channels")
async def update_notification_channels(
    request: Request, payload: UpdateNotificationChannelsPayload
) -> dict[str, Any]:
    """Persist APNs and/or webhook channels into config.yaml while preserving existing secrets."""
    manager = get_config_manager()
    current = manager.config.notifications
    existing_wh_by_id = {wh.id: wh for wh in current.webhooks}

    if payload.apns is not None:
        apns_dict = current.apns.model_dump()
        apns_patch = payload.apns.model_dump(exclude_unset=True)
        apns_dict.update({k: v for k, v in apns_patch.items() if v is not None})
        new_apns = APNsConfig.model_validate(apns_dict)
    else:
        new_apns = current.apns

    if payload.webhooks is not None:
        new_webhooks: list[WebhookChannelConfig] = []
        for item in payload.webhooks:
            wid = item.id.strip() or str(uuid4())
            existing_wh = existing_wh_by_id.get(wid)

            bot_token = item.bot_token
            if is_masked_or_empty(bot_token):
                bot_token = existing_wh.bot_token if existing_wh else ""

            merged_headers: dict[str, str] = {}
            old_headers = existing_wh.headers if existing_wh else {}
            for hk, hv in item.headers.items():
                if is_masked_or_empty(hv) and hk in old_headers:
                    merged_headers[hk] = old_headers[hk]
                else:
                    merged_headers[hk] = hv

            new_webhooks.append(
                WebhookChannelConfig.model_validate(
                    {
                        "id": wid,
                        "name": item.name,
                        "type": item.type,
                        "enabled": item.enabled,
                        "url": item.url,
                        "bot_token": bot_token or "",
                        "chat_id": item.chat_id,
                        "headers": merged_headers,
                        "notify_on_down": item.notify_on_down,
                        "notify_on_recovery": item.notify_on_recovery,
                        "include_details": item.include_details,
                    }
                )
            )
    else:
        new_webhooks = list(current.webhooks)

    updated = NotificationsConfig(apns=new_apns, webhooks=new_webhooks)
    saved_cfg = manager.update_section(
        "notifications",
        updated,
        preserve_templates=True,
        source="notifications_update",
    )

    store = _require_state_store(request)
    devices = await store.list_apns_devices()
    summary = _serialize_channels_summary(saved_cfg.notifications, devices)
    return {"ok": True, **summary}


@router.post("/test")
async def test_notification_channels(
    request: Request, payload: TestNotificationPayload
) -> dict[str, Any]:
    """Dispatch a live test notification to selected or all configured channels."""
    cfg = get_config_manager().config
    store = _require_state_store(request)

    dispatcher = getattr(request.app.state, "notification_dispatcher", None)
    if dispatcher is None:
        dispatcher = NotificationDispatcher(
            state_store=store,
            config_getter=lambda: get_config_manager().config,
            http_client=request.app.state.media_http,
        )

    event = NotificationEvent(
        event="test",
        title=payload.title or f"🔔 Test PVE Command Center ({cfg.server.name})",
        message=payload.message
        or "Ceci est une notification de test envoyée depuis PVE Command Center.",
        severity="info",
        service_id="pve-panel-test",
        service_name=cfg.server.name,
        status="up",
        latency_ms=12,
        timestamp=utc_now_iso(),
        details=f"Canal testé : {payload.channel_id or payload.channel_type}",
    )
    results = await dispatcher.dispatch_event(
        event,
        notifications_config=cfg.notifications,
        channel_id=payload.channel_id,
        channel_type=payload.channel_type,
        is_test=True,
    )
    return {
        "ok": any(item["ok"] for item in results) if results else False,
        "results": results,
    }
