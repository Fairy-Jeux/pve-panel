"""Bonjour / mDNS service publisher and bounded LAN discovery scanner."""

from __future__ import annotations

import asyncio
import hashlib
import ipaddress
import logging
import re
import socket
from typing import Any, Callable

logger = logging.getLogger(__name__)

DEFAULT_DISCOVERY_TYPES: tuple[str, ...] = (
    "_pvecenter._tcp.local.",
    "_http._tcp.local.",
    "_ssh._tcp.local.",
    "_smb._tcp.local.",
)

_PROTOCOL_BY_TYPE: dict[str, str] = {
    "_pvecenter._tcp.local.": "http_rest",
    "_http._tcp.local.": "http_rest",
    "_https._tcp.local.": "http_rest",
    "_ssh._tcp.local.": "tcp_port",
    "_smb._tcp.local.": "tcp_port",
}


def _cfg_get(obj: Any, key: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


def get_primary_lan_ip() -> str:
    """Detect the primary non-loopback IPv4 LAN address for mDNS advertisement."""
    try:
        with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
            sock.connect(("192.0.2.1", 80))
            candidate = sock.getsockname()[0]
            ip = ipaddress.ip_address(candidate)
            if not ip.is_loopback and not ip.is_link_local:
                return candidate
    except OSError:
        pass

    try:
        for info in socket.getaddrinfo(socket.gethostname(), None, socket.AF_INET):
            candidate = str(info[4][0])
            try:
                ip = ipaddress.ip_address(candidate)
            except ValueError:
                continue
            if not ip.is_loopback and not ip.is_link_local:
                return candidate
    except OSError:
        pass

    return "127.0.0.1"


def normalize_service_type(service_type: str | None) -> str:
    """Normalize an mDNS service type to end with '.local.'."""
    raw = (service_type or "_pvecenter._tcp.local.").strip()
    if not raw:
        return "_pvecenter._tcp.local."
    if not raw.endswith("."):
        raw += "."
    if not raw.endswith(".local."):
        raw = f"{raw.rstrip('.')}.local."
    return raw


def normalize_instance_name(raw_name: str | None, fallback: str = "PVE Command Center") -> str:
    """Sanitize a Bonjour instance label to avoid dot/control-character issues."""
    cleaned = re.sub(r"[\x00-\x1f.]+", " ", (raw_name or "").strip())
    cleaned = re.sub(r"\s+", " ", cleaned).strip()
    return (cleaned or fallback)[:63]


def suggested_protocol_for_service_type(service_type: str) -> str:
    """Map an mDNS service type to a suggested PVE Command Center connector protocol."""
    norm = normalize_service_type(service_type).lower()
    return _PROTOCOL_BY_TYPE.get(norm, "tcp_port")


def decode_txt_properties(raw_props: dict[Any, Any] | None) -> dict[str, str]:
    """Decode zeroconf bytes/None TXT properties into clean UTF-8 strings."""
    if not raw_props:
        return {}
    decoded: dict[str, str] = {}
    for raw_k, raw_v in raw_props.items():
        key = (
            raw_k.decode("utf-8", errors="replace")
            if isinstance(raw_k, (bytes, bytearray))
            else str(raw_k)
        )
        if not key:
            continue
        if raw_v is None:
            decoded[key] = ""
        elif isinstance(raw_v, (bytes, bytearray)):
            decoded[key] = raw_v.decode("utf-8", errors="replace")
        else:
            decoded[key] = str(raw_v)
    return decoded


def extract_server_advertisement_spec(
    app_config: Any, *, version: str = "1.0.0"
) -> dict[str, Any]:
    """Build normalized mDNS registration parameters from an AppConfig or dict."""
    server = _cfg_get(app_config, "server", app_config) or {}
    enabled = bool(_cfg_get(server, "mdns_enabled", True))
    server_id = str(_cfg_get(server, "id", "pve-center") or "pve-center").strip()
    name = str(_cfg_get(server, "name", "PVE Command Center") or "PVE Command Center").strip()
    service_name = str(
        _cfg_get(server, "mdns_service_name", "") or name or "PVE Command Center"
    ).strip()
    service_type = normalize_service_type(
        str(_cfg_get(server, "mdns_service_type", "_pvecenter._tcp.local."))
    )
    port = int(_cfg_get(server, "listen_port", 8000) or 8000)
    public_url = str(_cfg_get(server, "public_url", "") or "").strip()
    https = public_url.lower().startswith("https://")
    return {
        "enabled": enabled,
        "server_id": server_id,
        "name": name,
        "instance_name": normalize_instance_name(service_name, fallback=name or "PVE Command Center"),
        "service_type": service_type,
        "port": port,
        "https": https,
        "public_url": public_url,
        "version": version,
    }


class MDNSPublisher:
    """Manages AsyncZeroconf _pvecenter._tcp.local. registration across reloads."""

    def __init__(
        self,
        *,
        config_getter: Callable[[], Any] | None = None,
        version: str = "1.0.0",
    ) -> None:
        self._config_getter = config_getter
        self._version = version
        self._lock = asyncio.Lock()
        self._aiozc: Any = None
        self._current_info: Any = None
        self._current_signature: tuple[Any, ...] | None = None
        self._started = False

    def _build_service_info(self, spec: dict[str, Any]) -> tuple[Any, tuple[Any, ...]]:
        from zeroconf import ServiceInfo

        ip_str = get_primary_lan_ip()
        service_type = normalize_service_type(spec["service_type"])
        instance_name = normalize_instance_name(spec["instance_name"])
        full_name = f"{instance_name}.{service_type}"
        port = int(spec["port"])
        txt = {
            "id": str(spec["server_id"])[:128],
            "name": str(spec["name"])[:128],
            "version": str(spec.get("version") or self._version)[:32],
            "port": str(port),
            "https": "true" if spec.get("https") else "false",
            "public_url": str(spec.get("public_url") or "")[:200],
        }
        hostname = re.sub(r"[^a-zA-Z0-9-]", "-", socket.gethostname().split(".")[0]) or "pve-panel"
        info = ServiceInfo(
            type_=service_type,
            name=full_name,
            addresses=[socket.inet_aton(ip_str)],
            port=port,
            properties=txt,
            server=f"{hostname}.local.",
        )
        signature = (
            service_type,
            full_name,
            ip_str,
            port,
            tuple(sorted(txt.items())),
        )
        return info, signature

    async def _unregister_current(self) -> None:
        if self._aiozc is not None and self._current_info is not None:
            try:
                await self._aiozc.async_unregister_service(self._current_info)
            except Exception as exc:
                logger.debug("Erreur lors de la désinscription mDNS : %s", exc)
        self._current_info = None
        self._current_signature = None

    async def apply_config(self, app_config: Any) -> bool:
        """Register, update, or unregister mDNS advertisement based on configuration."""
        spec = extract_server_advertisement_spec(app_config, version=self._version)
        async with self._lock:
            if not spec["enabled"]:
                await self._unregister_current()
                return False

            try:
                from zeroconf.asyncio import AsyncZeroconf

                info, signature = self._build_service_info(spec)
                if self._current_signature == signature and self._current_info is not None:
                    return True

                if self._aiozc is None:
                    self._aiozc = AsyncZeroconf()

                await self._unregister_current()
                await self._aiozc.async_register_service(info)
                self._current_info = info
                self._current_signature = signature
                self._started = True
                logger.info(
                    "mDNS publié : %s (%s:%s)",
                    info.name,
                    get_primary_lan_ip(),
                    spec["port"],
                )
                return True
            except ImportError:
                logger.warning("zeroconf non installé : publication mDNS désactivée.")
                return False
            except OSError as exc:
                logger.warning("mDNS indisponible sur cet environnement : %s", exc)
                return False
            except Exception as exc:
                logger.warning("Erreur publication mDNS : %s", exc)
                return False

    async def start(self, app_config: Any = None) -> bool:
        """Start mDNS advertisement from explicit config or configured getter."""
        cfg = app_config if app_config is not None else (
            self._config_getter() if self._config_getter else {}
        )
        return await self.apply_config(cfg)

    async def reload(self, app_config: Any = None) -> bool:
        """Re-evaluate advertisement on configuration reload."""
        cfg = app_config if app_config is not None else (
            self._config_getter() if self._config_getter else {}
        )
        return await self.apply_config(cfg)

    async def stop(self) -> None:
        """Unregister advertised service and close AsyncZeroconf."""
        async with self._lock:
            await self._unregister_current()
            if self._aiozc is not None:
                try:
                    await self._aiozc.async_close()
                except Exception as exc:
                    logger.debug("Erreur fermeture AsyncZeroconf : %s", exc)
                self._aiozc = None
            self._started = False


async def discover_lan_services(
    *,
    timeout: float = 2.0,
    service_types: tuple[str, ...] = DEFAULT_DISCOVERY_TYPES,
) -> list[dict[str, Any]]:
    """Run a bounded async mDNS scan on the LAN and return deduplicated service entries."""
    try:
        from zeroconf import ServiceStateChange
        from zeroconf.asyncio import AsyncServiceBrowser, AsyncServiceInfo, AsyncZeroconf
    except ImportError:
        logger.warning("zeroconf non installé : scan LAN mDNS impossible.")
        return []

    loop = asyncio.get_running_loop()
    discovered: list[tuple[str, str]] = []
    seen_raw: set[tuple[str, str]] = set()
    first_seen_event = asyncio.Event()

    def _on_service_state_change(
        zeroconf: Any,
        service_type: str,
        name: str,
        state_change: Any,
    ) -> None:
        if state_change in (ServiceStateChange.Added, ServiceStateChange.Updated):
            key = (service_type, name)
            if key not in seen_raw:
                seen_raw.add(key)
                discovered.append(key)
                loop.call_soon_threadsafe(first_seen_event.set)

    bounded_timeout = max(0.3, min(float(timeout), 5.0))
    aiozc: Any = None
    browser: Any = None
    try:
        aiozc = AsyncZeroconf()
        browser = AsyncServiceBrowser(
            aiozc.zeroconf,
            list(service_types),
            handlers=[_on_service_state_change],
        )
        # Allow bounded discovery window for mDNS responses
        listen_window = min(bounded_timeout, 1.5)
        await asyncio.sleep(listen_window)

        results_map: dict[tuple[str, str, int], dict[str, Any]] = {}

        async def _resolve_one(svc_type: str, full_name: str) -> None:
            info = AsyncServiceInfo(svc_type, full_name)
            try:
                ok = await info.async_request(aiozc.zeroconf, timeout=500)
            except Exception:
                ok = False
            if not ok:
                return

            addresses = info.parsed_scoped_addresses()
            host = addresses[0] if addresses else (info.server or "").rstrip(".")
            if not host:
                return
            port = int(info.port or 0)
            if port <= 0:
                return

            norm_type = normalize_service_type(svc_type)
            dedup_key = (norm_type, host, port)
            if dedup_key in results_map:
                return

            suffix = f".{norm_type}"
            display_name = full_name[:-len(suffix)] if full_name.endswith(suffix) else full_name
            txt = decode_txt_properties(info.properties)
            stable_id = hashlib.sha1(
                f"{norm_type}|{host}|{port}".encode("utf-8")
            ).hexdigest()[:12]

            results_map[dedup_key] = {
                "id": txt.get("id") or stable_id,
                "name": txt.get("name") or display_name,
                "service_type": norm_type,
                "host": host,
                "port": port,
                "txt": txt,
                "suggested_protocol": suggested_protocol_for_service_type(norm_type),
            }

        if discovered:
            await asyncio.wait_for(
                asyncio.gather(*(_resolve_one(t, n) for t, n in discovered)),
                timeout=max(0.5, bounded_timeout - listen_window + 0.5),
            )

        return sorted(
            results_map.values(),
            key=lambda item: (item["service_type"], item["name"].lower(), item["host"]),
        )
    except OSError as exc:
        logger.warning("Scan LAN mDNS indisponible : %s", exc)
        return []
    except Exception as exc:
        logger.warning("Erreur scan LAN mDNS : %s", exc)
        return []
    finally:
        if browser is not None:
            try:
                await browser.async_cancel()
            except Exception:
                pass
        if aiozc is not None:
            try:
                await aiozc.async_close()
            except Exception:
                pass
