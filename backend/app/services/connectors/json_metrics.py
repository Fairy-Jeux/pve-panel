"""JSON HTTP endpoint connector with dotted path metric extraction."""

from __future__ import annotations

import re
from typing import Any

import httpx

from app.services.connectors.base import (
    ConnectorResult,
    cfg_get,
    perform_http_request,
    resolve_http_target,
)

_BRACKET_INDEX_RE = re.compile(r"^([^\[\]]+)\[(\d+)\]$")


def extract_dotted_path(data: Any, path: str) -> tuple[bool, Any]:
    """Traverse dicts and list indices along a dotted path such as 'stats.active_users'."""
    current = data
    for raw_part in path.strip().split("."):
        part = raw_part.strip()
        if not part:
            return False, None

        bracket_match = _BRACKET_INDEX_RE.match(part)
        if bracket_match:
            key_name, idx_str = bracket_match.groups()
            if not isinstance(current, dict) or key_name not in current:
                return False, None
            current = current[key_name]
            idx = int(idx_str)
            if not isinstance(current, list) or idx >= len(current):
                return False, None
            current = current[idx]
            continue

        if isinstance(current, dict):
            if part not in current:
                return False, None
            current = current[part]
        elif isinstance(current, list) and part.isdigit():
            idx = int(part)
            if idx < 0 or idx >= len(current):
                return False, None
            current = current[idx]
        else:
            return False, None

    return True, current


def _parse_metric_spec(spec: Any) -> list[tuple[str, str]]:
    """Parse string/list/dict metric specs into [(output_key, dotted_path), ...]."""
    if not spec:
        return []
    if isinstance(spec, dict):
        return [(str(k).strip(), str(v).strip()) for k, v in spec.items() if k and v]
    if isinstance(spec, (list, tuple)):
        items: list[tuple[str, str]] = []
        for entry in spec:
            items.extend(_parse_metric_spec(entry))
        return items

    raw = str(spec).strip()
    if not raw:
        return []
    pairs: list[tuple[str, str]] = []
    for chunk in re.split(r"[,;\n]+", raw):
        token = chunk.strip()
        if not token:
            continue
        if "=" in token:
            alias, path = token.split("=", 1)
            alias, path = alias.strip(), path.strip()
            if alias and path:
                pairs.append((alias, path))
        else:
            pairs.append((token, token))
    return pairs


def extract_metrics_from_json(
    data: Any, metric_spec: Any = None
) -> tuple[dict[str, Any], list[str]]:
    """Extract requested dotted paths (or top-level scalars when spec is omitted)."""
    pairs = _parse_metric_spec(metric_spec)
    if not pairs:
        if isinstance(data, dict):
            scalars = {
                str(k): v
                for k, v in data.items()
                if isinstance(v, (str, int, float, bool))
            }
            return dict(list(scalars.items())[:10]), []
        return {}, []

    metrics: dict[str, Any] = {}
    missing: list[str] = []
    for output_key, path in pairs:
        found, value = extract_dotted_path(data, path)
        if found:
            metrics[output_key] = value
        else:
            missing.append(path)
    return metrics, missing


async def check(
    service_config: Any,
    *,
    client: httpx.AsyncClient | None = None,
    timeout: float = 4.0,
) -> ConnectorResult:
    """Fetch JSON over HTTP and extract configured dotted metric paths."""
    target_url = resolve_http_target(service_config)
    if not target_url:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message="URL JSON manquante",
            metrics={},
        )

    expected_status = cfg_get(service_config, "expected_status", 200)
    metric_spec = cfg_get(service_config, "json_metric_path", None)

    try:
        resp, latency_ms = await perform_http_request(
            service_config,
            client=client,
            method="GET",
            timeout=timeout,
        )
        status_ok = (
            resp.status_code == int(expected_status)
            if expected_status not in (None, "", 0)
            else 200 <= resp.status_code < 400
        )
        if not status_ok:
            return ConnectorResult(
                ok=False,
                status="down",
                latency_ms=latency_ms,
                http_status=resp.status_code,
                message=f"HTTP {resp.status_code} lors de la lecture JSON",
                metrics={},
            )

        try:
            payload = resp.json()
        except ValueError:
            return ConnectorResult(
                ok=False,
                status="degraded",
                latency_ms=latency_ms,
                http_status=resp.status_code,
                message="Réponse HTTP reçue mais JSON invalide",
                metrics={},
            )

        metrics, missing = extract_metrics_from_json(payload, metric_spec)
        if metric_spec and missing and not metrics:
            return ConnectorResult(
                ok=False,
                status="degraded",
                latency_ms=latency_ms,
                http_status=resp.status_code,
                message=f"Chemin(s) JSON introuvable(s) : {', '.join(missing)}",
                metrics={},
            )

        msg = f"JSON OK ({len(metrics)} métrique(s))"
        if missing:
            msg += f" — manquant: {', '.join(missing)}"
        return ConnectorResult(
            ok=True,
            status="up",
            latency_ms=latency_ms,
            http_status=resp.status_code,
            message=msg,
            metrics=metrics,
        )
    except httpx.TimeoutException:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=int(timeout * 1000),
            http_status=None,
            message="Délai HTTP JSON dépassé (timeout)",
            metrics={},
        )
    except httpx.HTTPError as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"Erreur réseau JSON : {str(exc)[:120]}",
            metrics={},
        )
    except Exception as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"Erreur connecteur JSON : {str(exc)[:120]}",
            metrics={},
        )
