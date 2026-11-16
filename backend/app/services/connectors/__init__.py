"""Extensible connector registry for probing custom and built-in services."""

from __future__ import annotations

from typing import TYPE_CHECKING, Any

import httpx

from app.services.connectors import (
    http_rest,
    icmp_ping,
    json_metrics,
    tcp_port,
    webhook_ingest,
)
from app.services.connectors.base import ConnectorResult, cfg_get

if TYPE_CHECKING:
    from app.services.state_store import StateStore

SUPPORTED_PROTOCOLS = frozenset(
    {"http_rest", "tcp_port", "icmp_ping", "json_metrics", "webhook_ingest"}
)

__all__ = [
    "ConnectorResult",
    "SUPPORTED_PROTOCOLS",
    "http_rest",
    "icmp_ping",
    "json_metrics",
    "run_connector",
    "tcp_port",
    "webhook_ingest",
]


async def run_connector(
    service_config: Any,
    *,
    http_client: httpx.AsyncClient | None = None,
    state_store: StateStore | None = None,
    timeout: float | None = None,
) -> ConnectorResult:
    """Dispatch a service health/metrics check to the appropriate protocol connector."""
    protocol = str(cfg_get(service_config, "protocol", "http_rest") or "http_rest").strip().lower()

    if protocol == "http_rest":
        return await http_rest.check(
            service_config, client=http_client, timeout=timeout or 4.0
        )
    if protocol == "tcp_port":
        return await tcp_port.check(service_config, timeout=timeout or 3.0)
    if protocol == "icmp_ping":
        return await icmp_ping.check(service_config, timeout=timeout or 2.0)
    if protocol == "json_metrics":
        return await json_metrics.check(
            service_config, client=http_client, timeout=timeout or 4.0
        )
    if protocol == "webhook_ingest":
        return await webhook_ingest.check(service_config, state_store=state_store)

    return ConnectorResult(
        ok=False,
        status="down",
        latency_ms=0,
        http_status=None,
        message=f"Protocole connecteur non pris en charge : {protocol}",
        metrics={},
    )
