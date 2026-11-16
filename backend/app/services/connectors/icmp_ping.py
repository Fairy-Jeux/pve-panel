"""ICMP ping connector using system ping subprocess across macOS and Linux."""

from __future__ import annotations

import asyncio
import platform
import re
import shutil
import time
from typing import Any

from app.services.connectors.base import ConnectorResult, cfg_get, resolve_host_and_port

_RTT_TIME_RE = re.compile(r"time[=<]\s*([0-9]+(?:\.[0-9]+)?)\s*ms", re.IGNORECASE)
_RTT_SUMMARY_RE = re.compile(
    r"(?:round-trip|rtt)\s+min/avg/max(?:/[a-z]+)?\s*=\s*[0-9.]+/([0-9.]+)/",
    re.IGNORECASE,
)


def _extract_rtt_ms(output: str) -> float | None:
    match = _RTT_TIME_RE.search(output)
    if match:
        return float(match.group(1))
    summary = _RTT_SUMMARY_RE.search(output)
    if summary:
        return float(summary.group(1))
    return None


def _build_ping_command(host: str, timeout_seconds: float) -> list[str]:
    system = platform.system().lower()
    if system == "darwin":
        wait_ms = max(500, int(round(timeout_seconds * 1000)))
        return ["ping", "-c", "1", "-W", str(wait_ms), host]
    wait_sec = max(1, int(round(timeout_seconds)))
    return ["ping", "-c", "1", "-W", str(wait_sec), host]


async def check(service_config: Any, *, timeout: float = 2.0) -> ConnectorResult:
    """Execute single-packet ICMP ping and parse RTT latency cleanly."""
    host, _ = resolve_host_and_port(service_config)
    if not host or host.startswith("-") or any(ch.isspace() for ch in host):
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message="Hôte ICMP invalide ou manquant",
            metrics={},
        )

    ping_bin = shutil.which("ping")
    if not ping_bin:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message="Binaire ping indisponible sur cet hôte",
            metrics={"host": host},
        )

    req_timeout = float(cfg_get(service_config, "timeout_seconds", None) or timeout)
    cmd = _build_ping_command(host, req_timeout)
    cmd[0] = ping_bin

    start = time.perf_counter()
    proc: asyncio.subprocess.Process | None = None
    try:
        proc = await asyncio.create_subprocess_exec(
            *cmd,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE,
        )
        stdout, stderr = await asyncio.wait_for(
            proc.communicate(), timeout=req_timeout + 1.5
        )
        elapsed_ms = max(0, int(round((time.perf_counter() - start) * 1000)))
        out_text = stdout.decode("utf-8", errors="replace")
        err_text = stderr.decode("utf-8", errors="replace")
        parsed_rtt = _extract_rtt_ms(out_text)
        latency_ms = (
            max(0, int(round(parsed_rtt))) if parsed_rtt is not None else elapsed_ms
        )

        if proc.returncode == 0:
            metrics: dict[str, Any] = {"host": host, "packet_loss": 0.0}
            if parsed_rtt is not None:
                metrics["rtt_ms"] = round(parsed_rtt, 2)
            return ConnectorResult(
                ok=True,
                status="up",
                latency_ms=latency_ms,
                http_status=None,
                message=f"ICMP {host} joignable ({latency_ms} ms)",
                metrics=metrics,
            )

        err_msg = (err_text or out_text).strip().splitlines()
        detail = err_msg[-1][:120] if err_msg else f"code {proc.returncode}"
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=latency_ms,
            http_status=None,
            message=f"ICMP {host} injoignable ({detail})",
            metrics={"host": host, "packet_loss": 100.0},
        )
    except asyncio.TimeoutError:
        if proc is not None and proc.returncode is None:
            try:
                proc.kill()
                await proc.wait()
            except ProcessLookupError:
                pass
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=int(req_timeout * 1000),
            http_status=None,
            message=f"Timeout ICMP ping vers {host}",
            metrics={"host": host},
        )
    except OSError as exc:
        return ConnectorResult(
            ok=False,
            status="down",
            latency_ms=0,
            http_status=None,
            message=f"Échec exécution ping : {exc}",
            metrics={"host": host},
        )
