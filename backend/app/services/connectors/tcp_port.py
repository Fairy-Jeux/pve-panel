"""TCP socket port reachability connector."""

from __future__ import annotations

import asyncio
import time
from typing import Any

from app.services.connectors.base import ConnectorResult, cfg_get, resolve_host_and_port


async def check(service_config: Any, *, timeout: float = 3.0) -> ConnectorResult:
    """Open an async TCP connection to host:port and measure connect latency."""
    host, port = resolve_host_and_port(service_config)
    req_timeout = float(cfg_get(service_config, "timeout_seconds", None) or timeout)

    if not host or port is None or not (1 <= port <= 65535):
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message="Hôte et port TCP valides requis",
            metrics={},
        )

    start = time.perf_counter()
    writer: asyncio.StreamWriter | None = None
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(host, port), timeout=req_timeout
        )
        latency_ms = max(0, int(round((time.perf_counter() - start) * 1000)))
        return ConnectorResult(
            ok=True,
            status="up",
            latency_ms=latency_ms,
            http_status=None,
            message=f"Port TCP {host}:{port} ouvert",
            metrics={"host": host, "port": port},
        )
    except asyncio.TimeoutError:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=int(req_timeout * 1000),
            http_status=None,
            message=f"Timeout TCP sur {host}:{port}",
            metrics={"host": host, "port": port},
        )
    except OSError as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"TCP {host}:{port} inaccessible ({exc.strerror or exc})",
            metrics={"host": host, "port": port},
        )
    finally:
        if writer is not None:
            writer.close()
            try:
                await writer.wait_closed()
            except Exception:
                pass
