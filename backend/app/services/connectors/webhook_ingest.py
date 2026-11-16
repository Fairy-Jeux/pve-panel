"""Push-based webhook ingest connector backed by StateStore heartbeat TTL."""

from __future__ import annotations

from datetime import datetime
from typing import TYPE_CHECKING, Any

from app.services.connectors.base import ConnectorResult, cfg_get
from app.services.state_store import parse_iso_datetime, utc_now

if TYPE_CHECKING:
    from app.services.state_store import StateStore


async def check(
    service_config: Any,
    *,
    state_store: StateStore | None = None,
    now: datetime | None = None,
) -> ConnectorResult:
    """Evaluate webhook_ingest service status from its latest heartbeat timestamp and TTL."""
    service_id = str(cfg_get(service_config, "id", "") or "").strip()
    if not service_id:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message="ID du service webhook manquant",
            metrics={},
        )

    if state_store is None:
        return ConnectorResult(
            ok=False,
            status="degraded",
            latency_ms=0,
            http_status=None,
            message="StateStore indisponible pour webhook_ingest",
            metrics={},
        )

    heartbeat = await state_store.get_webhook_heartbeat(service_id)
    if heartbeat is None:
        return ConnectorResult(
            ok=False,
            status="degraded",
            latency_ms=0,
            http_status=None,
            message="En attente du premier heartbeat webhook",
            metrics={},
        )

    configured_ttl = cfg_get(service_config, "webhook_ttl_seconds", None) or cfg_get(
        service_config, "ttl_seconds", None
    )
    if not configured_ttl:
        refresh_interval = int(cfg_get(service_config, "refresh_interval_seconds", 0) or 0)
        ttl_seconds = int(heartbeat.get("ttl_seconds") or max(refresh_interval * 3, 300))
    else:
        ttl_seconds = max(1, int(configured_ttl))

    ref_now = now or utc_now()
    received_dt = parse_iso_datetime(heartbeat.get("received_at"))
    age_seconds = (
        max(0.0, (ref_now - received_dt).total_seconds())
        if received_dt is not None
        else float(ttl_seconds + 1)
    )

    metrics = dict(heartbeat.get("metrics") or {})
    metrics["heartbeat_age_seconds"] = int(age_seconds)
    metrics["ttl_seconds"] = ttl_seconds
    metrics["last_heartbeat_at"] = heartbeat.get("received_at")

    if age_seconds > ttl_seconds:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"Heartbeat webhook expiré ({int(age_seconds)}s > {ttl_seconds}s)",
            metrics=metrics,
        )

    reported_status = str(heartbeat.get("status") or "up").strip().lower()
    msg = str(heartbeat.get("message") or "").strip()
    if reported_status == "down":
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=msg or "Statut DOWN signalé par webhook",
            metrics=metrics,
        )
    if reported_status == "degraded":
        return ConnectorResult(
            ok=False,
            status="degraded",
            latency_ms=0,
            http_status=None,
            message=msg or "Statut dégradé signalé par webhook",
            metrics=metrics,
        )

    return ConnectorResult(
        ok=True,
        status="up",
        latency_ms=0,
        http_status=None,
        message=msg or f"Heartbeat actif ({int(age_seconds)}s / {ttl_seconds}s)",
        metrics=metrics,
    )
