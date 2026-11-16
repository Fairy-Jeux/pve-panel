"""HTTP/HTTPS REST healthcheck connector."""

from __future__ import annotations

from typing import Any

import httpx

from app.services.connectors.base import (
    ConnectorResult,
    cfg_get,
    perform_http_request,
    resolve_http_target,
)


def _match_expected_status(actual: int, expected: Any) -> tuple[bool, str | None]:
    if expected in (None, "", 0):
        if 200 <= actual < 400:
            return True, None
        return False, f"HTTP {actual}"
    if isinstance(expected, (list, tuple, set)):
        allowed = {int(code) for code in expected}
        if actual in allowed:
            return True, None
        return False, f"HTTP {actual} (attendu: {sorted(allowed)})"
    expected_int = int(expected)
    if actual == expected_int:
        return True, None
    return False, f"HTTP {actual} (attendu: {expected_int})"


async def check(
    service_config: Any,
    *,
    client: httpx.AsyncClient | None = None,
    timeout: float = 4.0,
) -> ConnectorResult:
    """Perform an async HTTP GET/HEAD check with auth, SSL option, and status matching."""
    target_url = resolve_http_target(service_config)
    if not target_url:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message="URL HTTP manquante",
            metrics={},
        )

    expected_status = cfg_get(service_config, "expected_status", 200)
    try:
        resp, latency_ms = await perform_http_request(
            service_config,
            client=client,
            timeout=timeout,
        )
        matched, mismatch_msg = _match_expected_status(resp.status_code, expected_status)
        if matched:
            return ConnectorResult(
                ok=True,
                status="up",
                latency_ms=latency_ms,
                http_status=resp.status_code,
                message=f"HTTP {resp.status_code} OK",
                metrics={"http_status": resp.status_code},
            )
        status = (
            "degraded"
            if expected_status in (None, "", 0) and 400 <= resp.status_code < 500
            else "down"
        )
        return ConnectorResult(
            ok=False,
            status=status,
            latency_ms=latency_ms,
            http_status=resp.status_code,
            message=mismatch_msg or f"HTTP {resp.status_code}",
            metrics={"http_status": resp.status_code},
        )
    except ValueError as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=str(exc),
            metrics={},
        )
    except httpx.TimeoutException:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=int(timeout * 1000),
            http_status=None,
            message="Délai HTTP dépassé (timeout)",
            metrics={},
        )
    except httpx.HTTPError as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"Erreur HTTP : {str(exc)[:120]}",
            metrics={},
        )
    except Exception as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"Erreur connecteur HTTP : {str(exc)[:120]}",
            metrics={},
        )
