"""Shared dataclass and HTTP/config helpers for service connectors."""

from __future__ import annotations

import base64
from dataclasses import asdict, dataclass, field
import time
from typing import Any
from urllib.parse import urlparse

import httpx


@dataclass(slots=True)
class ConnectorResult:
    """Normalized health and metrics result returned by every connector."""

    ok: bool
    status: str  # "up" | "degraded" | "down"
    latency_ms: int
    http_status: int | None
    message: str
    metrics: dict[str, Any] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        """Serialize result to a plain snake_case dictionary."""
        return asdict(self)


def cfg_get(config: Any, key: str, default: Any = None) -> Any:
    """Read a field cleanly from either a dict or a Pydantic/object config."""
    if isinstance(config, dict):
        return config.get(key, default)
    return getattr(config, key, default)


def resolve_host_and_port(config: Any) -> tuple[str, int | None]:
    """Extract target host and optional port from host/port or URL fields."""
    raw_host = str(cfg_get(config, "host", "") or "").strip()
    raw_port = cfg_get(config, "port", None)
    port: int | None = None
    if raw_port not in (None, ""):
        try:
            port = int(raw_port)
        except (TypeError, ValueError):
            port = None

    if raw_host and "://" not in raw_host:
        if ":" in raw_host and raw_host.count(":") == 1 and port is None:
            host_part, port_part = raw_host.split(":", 1)
            if port_part.isdigit():
                return host_part.strip(), int(port_part)
        return raw_host, port

    candidate_url = (
        raw_host
        or str(cfg_get(config, "health_url", "") or "").strip()
        or str(cfg_get(config, "internal_url", "") or "").strip()
        or str(cfg_get(config, "ping_url", "") or "").strip()
        or str(cfg_get(config, "url", "") or "").strip()
    )
    if not candidate_url:
        return "", port

    parsed = urlparse(candidate_url if "://" in candidate_url else f"http://{candidate_url}")
    host = (parsed.hostname or "").strip()
    if port is None:
        if parsed.port is not None:
            port = parsed.port
        elif parsed.scheme == "https":
            port = 443
        elif parsed.scheme == "http":
            port = 80
    return host, port


def resolve_http_target(config: Any) -> str:
    """Choose the best HTTP target URL from health_url, internal_url, ping_url, url, or host/port."""
    for field_name in ("health_url", "internal_url", "ping_url", "url"):
        val = str(cfg_get(config, field_name, "") or "").strip()
        if val:
            if "://" not in val:
                return f"http://{val}"
            return val

    host = str(cfg_get(config, "host", "") or "").strip()
    if not host:
        return ""
    if "://" in host:
        return host
    port = cfg_get(config, "port", None)
    scheme = "https" if str(port) == "443" else "http"
    if port not in (None, ""):
        return f"{scheme}://{host}:{port}"
    return f"{scheme}://{host}"


def _encode_basic_token(raw_token: str, username: str = "") -> str:
    """Encode Basic auth credentials safely from user:pass, pre-encoded base64, or username+token."""
    if username and ":" not in raw_token:
        raw = f"{username}:{raw_token}"
        return base64.b64encode(raw.encode("utf-8")).decode("ascii")
    if ":" in raw_token:
        return base64.b64encode(raw_token.encode("utf-8")).decode("ascii")
    try:
        decoded = base64.b64decode(raw_token.encode("ascii"), validate=True).decode("utf-8")
        if ":" in decoded:
            return raw_token
    except Exception:
        pass
    return base64.b64encode(raw_token.encode("utf-8")).decode("ascii")


def build_http_headers(config: Any) -> dict[str, str]:
    """Construct optional authentication and custom headers for HTTP connectors."""
    headers: dict[str, str] = {}
    extra_headers = cfg_get(config, "headers", None)
    if isinstance(extra_headers, dict):
        for k, v in extra_headers.items():
            if k and v is not None:
                headers[str(k)] = str(v)

    auth_type = str(cfg_get(config, "auth_type", "none") or "none").strip().lower()
    auth_token = str(cfg_get(config, "auth_token", "") or "")
    auth_username = str(cfg_get(config, "auth_username", "") or "")
    auth_header_name = str(cfg_get(config, "auth_header_name", "") or "X-API-Key").strip()

    if not auth_token or auth_type == "none":
        return headers

    if auth_type == "bearer":
        headers["Authorization"] = f"Bearer {auth_token}"
    elif auth_type == "basic":
        headers["Authorization"] = f"Basic {_encode_basic_token(auth_token, auth_username)}"
    elif auth_type == "header":
        headers[auth_header_name or "X-API-Key"] = auth_token

    return headers


async def perform_http_request(
    config: Any,
    *,
    client: httpx.AsyncClient | None = None,
    method: str | None = None,
    timeout: float = 4.0,
) -> tuple[httpx.Response, int]:
    """Execute an async HTTP request respecting auth headers, SSL option, and latency."""
    target_url = resolve_http_target(config)
    if not target_url:
        raise ValueError("URL ou hôte HTTP manquant.")

    parsed = urlparse(target_url)
    if parsed.scheme not in ("http", "https") or not parsed.netloc:
        raise ValueError(f"URL HTTP invalide : {target_url}")

    req_method = (method or str(cfg_get(config, "method", "GET") or "GET")).strip().upper()
    if req_method not in ("GET", "HEAD"):
        req_method = "GET"

    headers = build_http_headers(config)
    req_timeout = float(cfg_get(config, "timeout_seconds", None) or timeout)
    verify_ssl = cfg_get(config, "verify_ssl", None)

    start = time.perf_counter()
    use_external_client = client is not None and (
        verify_ssl is None
        or not isinstance(getattr(client, "_transport", None), httpx.AsyncHTTPTransport)
        or not bool(verify_ssl)
    )
    if use_external_client and client is not None:
        resp = await client.request(
            req_method,
            target_url,
            headers=headers,
            follow_redirects=True,
            timeout=req_timeout,
        )
    else:
        async with httpx.AsyncClient(
            verify=bool(verify_ssl) if verify_ssl is not None else False,
            timeout=httpx.Timeout(req_timeout, connect=min(req_timeout, 3.0)),
        ) as temp_client:
            resp = await temp_client.request(
                req_method,
                target_url,
                headers=headers,
                follow_redirects=True,
            )

    latency_ms = max(0, int(round((time.perf_counter() - start) * 1000)))
    return resp, latency_ms
