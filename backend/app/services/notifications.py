"""Multi-channel notification dispatcher (APNs HTTP/2, Discord, Telegram, Generic JSON)."""

from __future__ import annotations

import asyncio
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
import logging
from pathlib import Path
import time
from typing import Any, Callable

import httpx

from app.services.state_store import StateStore

logger = logging.getLogger(__name__)

DISCORD_COLOR_DOWN = 0xEF4444
DISCORD_COLOR_DEGRADED = 0xF59E0B
DISCORD_COLOR_UP = 0x10B981

_MDV2_SPECIAL_CHARS = r"_*[]()~`>#+-=|{}.!"


def escape_markdown_v2(text: str) -> str:
    """Escape Telegram MarkdownV2 reserved characters cleanly."""
    escaped = str(text or "").replace("\\", "\\\\")
    for ch in _MDV2_SPECIAL_CHARS:
        escaped = escaped.replace(ch, f"\\{ch}")
    return escaped


def _cfg_get(obj: Any, key: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


@dataclass(slots=True)
class NotificationEvent:
    """Normalized alert or test notification payload."""

    event: str  # "alert_triggered" | "alert_resolved" | "test"
    title: str
    message: str
    severity: str  # "critical" | "warning" | "info"
    service_id: str
    service_name: str
    status: str  # "up" | "degraded" | "down"
    latency_ms: int | None = None
    timestamp: str = ""
    incident_id: str | None = None
    details: str | None = None

    def __post_init__(self) -> None:
        if not self.timestamp:
            self.timestamp = datetime.now(timezone.utc).isoformat()


@dataclass(slots=True)
class ChannelDeliveryResult:
    """Per-channel delivery outcome returned by NotificationDispatcher."""

    channel_id: str
    channel_name: str
    channel_type: str
    ok: bool
    skipped: bool
    http_status: int | None
    message: str

    def to_dict(self) -> dict[str, Any]:
        return asdict(self)


def build_discord_payload(event: NotificationEvent, *, include_details: bool = True) -> dict[str, Any]:
    """Build a Discord rich embed webhook payload."""
    status_lower = event.status.lower()
    if event.event == "alert_resolved" or status_lower == "up":
        color = DISCORD_COLOR_UP
    elif status_lower == "degraded" or event.severity.lower() == "warning":
        color = DISCORD_COLOR_DEGRADED
    else:
        color = DISCORD_COLOR_DOWN

    fields = [
        {"name": "Service", "value": event.service_name or event.service_id, "inline": True},
        {"name": "Statut", "value": event.status.upper(), "inline": True},
        {
            "name": "Latence",
            "value": f"{event.latency_ms} ms" if event.latency_ms is not None else "N/A",
            "inline": True,
        },
        {"name": "Horodatage", "value": event.timestamp, "inline": False},
    ]
    if include_details and event.details:
        fields.append({"name": "Détails", "value": event.details[:1000], "inline": False})

    return {
        "embeds": [
            {
                "title": event.title,
                "description": event.message,
                "color": color,
                "fields": fields,
                "timestamp": event.timestamp,
            }
        ]
    }


def build_telegram_text(event: NotificationEvent, *, include_details: bool = True) -> str:
    """Format a notification into Telegram MarkdownV2 text."""
    lines = [
        f"*{escape_markdown_v2(event.title)}*",
        escape_markdown_v2(event.message),
        "",
        f"• *Service* : `{escape_markdown_v2(event.service_name or event.service_id)}`",
        f"• *Statut* : `{escape_markdown_v2(event.status.upper())}`",
        f"• *Latence* : `{escape_markdown_v2(f'{event.latency_ms} ms' if event.latency_ms is not None else 'N/A')}`",
        f"• *Horodatage* : `{escape_markdown_v2(event.timestamp)}`",
    ]
    if include_details and event.details:
        lines.append(f"• *Détails* : {escape_markdown_v2(event.details[:400])}")
    return "\n".join(lines)


def build_generic_payload(event: NotificationEvent, *, include_details: bool = True) -> dict[str, Any]:
    """Build generic JSON webhook payload compatible with ntfy, Gotify, and Home Assistant."""
    payload: dict[str, Any] = {
        "event": event.event,
        "title": event.title,
        "message": event.message,
        "severity": event.severity,
        "service_id": event.service_id,
        "service_name": event.service_name,
        "status": event.status,
        "latency_ms": event.latency_ms,
        "timestamp": event.timestamp,
    }
    if event.incident_id:
        payload["incident_id"] = event.incident_id
    if include_details and event.details:
        payload["details"] = event.details
    return payload


def build_apns_payload(event: NotificationEvent) -> dict[str, Any]:
    """Build APNs alert JSON payload with SERVICE_ALERT category and mutable-content."""
    return {
        "aps": {
            "alert": {
                "title": event.title,
                "subtitle": event.service_name or event.service_id,
                "body": event.message,
            },
            "sound": "default",
            "mutable-content": 1,
            "category": "SERVICE_ALERT",
        },
        "event": event.event,
        "service_id": event.service_id,
        "service_name": event.service_name,
        "severity": event.severity,
        "status": event.status,
        "latency_ms": event.latency_ms,
        "incident_id": event.incident_id,
        "timestamp": event.timestamp,
    }


class NotificationDispatcher:
    """Dispatches alerts and test messages to APNs, Discord, Telegram, and generic webhooks."""

    def __init__(
        self,
        *,
        state_store: StateStore | None = None,
        config_getter: Callable[[], Any] | None = None,
        http_client: httpx.AsyncClient | None = None,
        apns_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._state_store = state_store
        self._config_getter = config_getter
        self._http_client = http_client
        self._apns_client = apns_client
        self._apns_jwt_cache: tuple[tuple[str, str, str], float, str] | None = None

    def _get_notifications_config(self, override: Any = None) -> Any:
        if override is not None:
            return override
        if self._config_getter is None:
            return {}
        cfg = self._config_getter()
        return _cfg_get(cfg, "notifications", cfg)

    def _get_apns_jwt(
        self, team_id: str, key_id: str, key_path: Path
    ) -> str:
        """Sign and cache an ES256 APNs provider token for 45 minutes."""
        cache_key = (team_id, key_id, str(key_path))
        now_mono = time.monotonic()
        if (
            self._apns_jwt_cache is not None
            and self._apns_jwt_cache[0] == cache_key
            and (now_mono - self._apns_jwt_cache[1]) < 2700
        ):
            return self._apns_jwt_cache[2]

        import jwt  # PyJWT[crypto]

        private_key = key_path.read_text(encoding="utf-8")
        issued_at = int(time.time())
        token = jwt.encode(
            {"iss": team_id, "iat": issued_at},
            private_key,
            algorithm="ES256",
            headers={"alg": "ES256", "kid": key_id},
        )
        if isinstance(token, bytes):
            token = token.decode("utf-8")
        self._apns_jwt_cache = (cache_key, now_mono, token)
        return token

    async def _send_apns(
        self, apns_cfg: Any, event: NotificationEvent, *, force_attempt: bool = False
    ) -> ChannelDeliveryResult:
        enabled = bool(_cfg_get(apns_cfg, "enabled", False))
        if not enabled and not force_attempt:
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=False,
                skipped=True,
                http_status=None,
                message="APNs désactivé dans la configuration",
            )

        team_id = str(_cfg_get(apns_cfg, "team_id", "") or "").strip()
        key_id = str(_cfg_get(apns_cfg, "key_id", "") or "").strip()
        bundle_id = str(_cfg_get(apns_cfg, "bundle_id", "io.ac.pvepanel.app") or "io.ac.pvepanel.app").strip()
        key_path_raw = str(_cfg_get(apns_cfg, "private_key_path", "/app/config/AuthKey.p8") or "").strip()
        use_sandbox = bool(_cfg_get(apns_cfg, "use_sandbox", False))

        if not team_id or not key_id or not key_path_raw:
            logger.warning("APNs ignoré : team_id, key_id ou private_key_path manquant.")
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=False,
                skipped=True,
                http_status=None,
                message="APNs ignoré : team_id, key_id ou private_key_path manquant",
            )

        key_path = Path(key_path_raw)
        if not key_path.is_file():
            logger.warning("APNs ignoré : fichier clé .p8 introuvable (%s).", key_path)
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=False,
                skipped=True,
                http_status=None,
                message=f"APNs ignoré : fichier .p8 introuvable ({key_path})",
            )

        if self._state_store is None:
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=False,
                skipped=True,
                http_status=None,
                message="APNs ignoré : StateStore indisponible",
            )

        devices = await self._state_store.list_apns_devices()
        if not devices:
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=False,
                skipped=True,
                http_status=None,
                message="Aucun appareil APNs enregistré",
            )

        try:
            provider_jwt = self._get_apns_jwt(team_id, key_id, key_path)
        except Exception as exc:
            logger.warning("APNs ignoré : erreur signature JWT ES256 (%s).", exc)
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=False,
                skipped=True,
                http_status=None,
                message=f"Erreur signature JWT APNs : {str(exc)[:120]}",
            )

        payload = build_apns_payload(event)
        headers = {
            "authorization": f"bearer {provider_jwt}",
            "apns-topic": bundle_id,
            "apns-push-type": "alert",
            "apns-priority": "10",
        }

        own_client = self._apns_client is None
        client = self._apns_client
        if own_client:
            try:
                client = httpx.AsyncClient(
                    http2=True, timeout=httpx.Timeout(6.0, connect=3.0)
                )
            except ImportError as exc:
                logger.warning("APNs ignoré : support HTTP/2 (h2) indisponible (%s).", exc)
                return ChannelDeliveryResult(
                    channel_id="apns",
                    channel_name="Apple Push (APNs)",
                    channel_type="apns",
                    ok=False,
                    skipped=True,
                    http_status=None,
                    message="Dépendance HTTP/2 (h2) manquante pour APNs",
                )

        assert client is not None
        successes = 0
        last_status: int | None = None
        errors: list[str] = []
        try:
            for dev in devices:
                token = dev["device_token"]
                dev_env = str(dev.get("environment") or "production").lower()
                is_sandbox = use_sandbox or dev_env == "sandbox"
                host = (
                    "https://api.sandbox.push.apple.com"
                    if is_sandbox
                    else "https://api.push.apple.com"
                )
                url = f"{host}/3/device/{token}"
                try:
                    resp = await client.post(url, json=payload, headers=headers)
                    last_status = resp.status_code
                    if 200 <= resp.status_code < 300:
                        successes += 1
                    else:
                        reason = resp.text[:120]
                        errors.append(f"{token[:8]}…: HTTP {resp.status_code} {reason}")
                        if resp.status_code == 410 and self._state_store is not None:
                            await self._state_store.delete_apns_device(token)
                except Exception as exc:
                    errors.append(f"{token[:8]}…: {str(exc)[:80]}")
        finally:
            if own_client:
                await client.aclose()

        if successes == len(devices):
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=True,
                skipped=False,
                http_status=last_status or 200,
                message=f"APNs envoyé à {successes}/{len(devices)} appareil(s)",
            )
        if successes > 0:
            return ChannelDeliveryResult(
                channel_id="apns",
                channel_name="Apple Push (APNs)",
                channel_type="apns",
                ok=True,
                skipped=False,
                http_status=last_status,
                message=f"APNs partiel {successes}/{len(devices)} ({'; '.join(errors[:2])})",
            )
        return ChannelDeliveryResult(
            channel_id="apns",
            channel_name="Apple Push (APNs)",
            channel_type="apns",
            ok=False,
            skipped=False,
            http_status=last_status,
            message=f"Échec APNs : {'; '.join(errors[:2])}",
        )

    async def _send_webhook(
        self, webhook: Any, event: NotificationEvent
    ) -> ChannelDeliveryResult:
        channel_id = str(_cfg_get(webhook, "id", "") or "webhook")
        channel_name = str(_cfg_get(webhook, "name", "") or channel_id)
        channel_type = str(_cfg_get(webhook, "type", "generic") or "generic").strip().lower()
        include_details = bool(_cfg_get(webhook, "include_details", True))

        own_client = self._http_client is None
        client = self._http_client or httpx.AsyncClient(
            verify=True, timeout=httpx.Timeout(6.0, connect=3.0)
        )
        try:
            if channel_type == "discord":
                url = str(_cfg_get(webhook, "url", "") or "").strip()
                if not url:
                    return ChannelDeliveryResult(
                        channel_id, channel_name, channel_type, False, True, None, "URL Discord manquante"
                    )
                resp = await client.post(
                    url, json=build_discord_payload(event, include_details=include_details)
                )
            elif channel_type == "telegram":
                bot_token = str(_cfg_get(webhook, "bot_token", "") or "").strip()
                chat_id = str(_cfg_get(webhook, "chat_id", "") or "").strip()
                if not bot_token or not chat_id:
                    return ChannelDeliveryResult(
                        channel_id,
                        channel_name,
                        channel_type,
                        False,
                        True,
                        None,
                        "bot_token ou chat_id Telegram manquant",
                    )
                base_url = str(_cfg_get(webhook, "url", "") or "https://api.telegram.org").rstrip("/")
                if "/bot" not in base_url:
                    tg_url = f"{base_url}/bot{bot_token}/sendMessage"
                else:
                    tg_url = base_url
                resp = await client.post(
                    tg_url,
                    json={
                        "chat_id": chat_id,
                        "text": build_telegram_text(event, include_details=include_details),
                        "parse_mode": "MarkdownV2",
                        "disable_web_page_preview": True,
                    },
                )
            else:
                url = str(_cfg_get(webhook, "url", "") or "").strip()
                if not url:
                    return ChannelDeliveryResult(
                        channel_id, channel_name, channel_type, False, True, None, "URL webhook manquante"
                    )
                raw_headers = _cfg_get(webhook, "headers", None)
                headers = (
                    {str(k): str(v) for k, v in raw_headers.items() if k and v is not None}
                    if isinstance(raw_headers, dict)
                    else {}
                )
                resp = await client.post(
                    url,
                    json=build_generic_payload(event, include_details=include_details),
                    headers=headers,
                )

            ok = 200 <= resp.status_code < 300
            if ok and channel_type == "telegram":
                try:
                    tg_json = resp.json()
                    if isinstance(tg_json, dict) and tg_json.get("ok") is False:
                        ok = False
                except ValueError:
                    pass

            msg = (
                f"Notification {channel_type} envoyée (HTTP {resp.status_code})"
                if ok
                else f"Erreur {channel_type} HTTP {resp.status_code}: {resp.text[:120]}"
            )
            return ChannelDeliveryResult(
                channel_id, channel_name, channel_type, ok, False, resp.status_code, msg
            )
        except Exception as exc:
            return ChannelDeliveryResult(
                channel_id,
                channel_name,
                channel_type,
                False,
                False,
                None,
                f"Erreur envoi {channel_type} : {str(exc)[:120]}",
            )
        finally:
            if own_client:
                await client.aclose()

    def _should_notify_webhook(self, webhook: Any, event: NotificationEvent) -> bool:
        if not bool(_cfg_get(webhook, "enabled", True)):
            return False
        if event.event == "alert_resolved":
            return bool(_cfg_get(webhook, "notify_on_recovery", True))
        if event.event == "alert_triggered":
            return bool(_cfg_get(webhook, "notify_on_down", True))
        return True

    async def dispatch_event(
        self,
        event: NotificationEvent,
        *,
        notifications_config: Any = None,
        channel_id: str | None = None,
        channel_type: str | None = None,
        is_test: bool = False,
    ) -> list[dict[str, Any]]:
        """Dispatch an event concurrently across matching notification channels."""
        notif_cfg = self._get_notifications_config(notifications_config)
        apns_cfg = _cfg_get(notif_cfg, "apns", {}) or {}
        webhooks = list(_cfg_get(notif_cfg, "webhooks", []) or [])

        req_type = (channel_type or "all").strip().lower()
        tasks = []

        include_apns = (
            (channel_id == "apns")
            or (channel_id is None and req_type in ("all", "apns"))
        )
        if include_apns:
            apns_enabled = bool(_cfg_get(apns_cfg, "enabled", False))
            if apns_enabled or (is_test and (channel_id == "apns" or req_type == "apns")):
                tasks.append(
                    self._send_apns(
                        apns_cfg,
                        event,
                        force_attempt=is_test and (channel_id == "apns" or req_type == "apns"),
                    )
                )

        for wh in webhooks:
            wh_id = str(_cfg_get(wh, "id", "") or "")
            wh_type = str(_cfg_get(wh, "type", "generic") or "generic").strip().lower()
            if channel_id is not None:
                if wh_id != channel_id:
                    continue
            elif req_type != "all" and wh_type != req_type:
                continue

            if not is_test and not self._should_notify_webhook(wh, event):
                continue
            if is_test and channel_id is None and req_type == "all" and not bool(_cfg_get(wh, "enabled", True)):
                continue

            tasks.append(self._send_webhook(wh, event))

        if not tasks:
            return []

        results = await asyncio.gather(*tasks)
        return [res.to_dict() for res in results]
