"""Background stateful alerting engine with debounce, cooldown, mute, and recovery."""

from __future__ import annotations

import asyncio
from datetime import datetime
import logging
import time
from typing import Any, Callable

import httpx

from app.config_manager import ConfigManager, get_config_manager
from app.config_schema import AppConfig, CustomServiceConfig
from app.services.connectors import ConnectorResult, run_connector
from app.services.notifications import NotificationDispatcher, NotificationEvent
from app.services.realtime_bus import RealtimeBus, get_realtime_bus
from app.services.state_store import (
    StateStore,
    parse_iso_datetime,
    utc_now,
)

logger = logging.getLogger(__name__)


def _cfg_get(obj: Any, key: str, default: Any = None) -> Any:
    if isinstance(obj, dict):
        return obj.get(key, default)
    return getattr(obj, key, default)


class AlertEngine:
    """Polls monitored services, manages incident lifecycles, and dispatches alerts."""

    def __init__(
        self,
        *,
        state_store: StateStore,
        dispatcher: NotificationDispatcher,
        config_manager: ConfigManager | None = None,
        config_getter: Callable[[], AppConfig] | None = None,
        bus: RealtimeBus | None = None,
        http_client: httpx.AsyncClient | None = None,
    ) -> None:
        self._state_store = state_store
        self._dispatcher = dispatcher
        self._config_manager = config_manager or get_config_manager()
        self._config_getter = config_getter or (lambda: self._config_manager.config)
        self._bus = bus or get_realtime_bus()
        self._http_client = http_client

        self._stop_event: asyncio.Event | None = None
        self._wake_event: asyncio.Event | None = None
        self._task: asyncio.Task[None] | None = None
        self._last_polled_mono: dict[str, float] = {}
        self._service_locks: dict[str, asyncio.Lock] = {}

    def _get_service_lock(self, service_id: str) -> asyncio.Lock:
        lock = self._service_locks.get(service_id)
        if lock is None:
            lock = asyncio.Lock()
            self._service_locks[service_id] = lock
        return lock

    def notify_config_reload(self, _cfg: AppConfig | None = None) -> None:
        """Wake the polling loop promptly when configuration changes."""
        if self._wake_event is not None:
            self._wake_event.set()

    async def start(self) -> None:
        """Start the background monitoring loop."""
        if self._task is not None and not self._task.done():
            return
        self._stop_event = asyncio.Event()
        self._wake_event = asyncio.Event()
        self._task = asyncio.create_task(self._poll_loop(), name="alert-engine")

    async def stop(self) -> None:
        """Stop the background monitoring loop gracefully."""
        if self._stop_event is not None:
            self._stop_event.set()
        if self._wake_event is not None:
            self._wake_event.set()
        if self._task is not None:
            try:
                await asyncio.wait_for(self._task, timeout=3.0)
            except (asyncio.TimeoutError, asyncio.CancelledError):
                self._task.cancel()
                try:
                    await self._task
                except asyncio.CancelledError:
                    pass
            self._task = None
            self._stop_event = None
            self._wake_event = None

    async def _poll_loop(self) -> None:
        assert self._stop_event is not None
        assert self._wake_event is not None
        while not self._stop_event.is_set():
            try:
                await self.run_once(force=False)
            except asyncio.CancelledError:
                raise
            except Exception as exc:
                logger.exception("Erreur dans la boucle AlertEngine : %s", exc)

            cfg = self._config_getter()
            tick_interval = max(1.0, float(min(cfg.alerts.check_interval_seconds, 15)))
            self._wake_event.clear()
            try:
                await asyncio.wait_for(self._wake_event.wait(), timeout=tick_interval)
            except asyncio.TimeoutError:
                pass

    def _collect_due_services(
        self, cfg: AppConfig, *, force: bool
    ) -> list[CustomServiceConfig]:
        now_mono = time.monotonic()
        global_interval = max(5, int(cfg.alerts.check_interval_seconds))
        due: list[CustomServiceConfig] = []

        for svc in cfg.custom_services:
            if not svc.enabled:
                continue
            effective_interval = max(
                5, int(svc.refresh_interval_seconds or global_interval)
            )
            last_mono = self._last_polled_mono.get(svc.id)
            if force or last_mono is None or (now_mono - last_mono) >= effective_interval:
                due.append(svc)
        return due

    async def run_once(self, *, force: bool = False) -> list[dict[str, Any]]:
        """Run one evaluation sweep for all due enabled custom services."""
        cfg = self._config_getter()
        due_services = self._collect_due_services(cfg, force=force)
        if not due_services:
            return []

        now_mono = time.monotonic()
        for svc in due_services:
            self._last_polled_mono[svc.id] = now_mono

        results = await asyncio.gather(
            *(self._check_and_evaluate(svc, cfg) for svc in due_services),
            return_exceptions=False,
        )
        return list(results)

    async def _check_and_evaluate(
        self, svc: CustomServiceConfig, cfg: AppConfig
    ) -> dict[str, Any]:
        connector_result = await run_connector(
            svc,
            http_client=self._http_client,
            state_store=self._state_store,
        )
        return await self.evaluate_service(
            svc, result=connector_result, app_config=cfg
        )

    async def evaluate_service(
        self,
        service_config: Any,
        *,
        result: ConnectorResult | None = None,
        app_config: AppConfig | None = None,
        now: datetime | None = None,
    ) -> dict[str, Any]:
        """Evaluate a connector result against stateful debounce/cooldown/mute rules."""
        cfg = app_config or self._config_getter()
        service_id = str(_cfg_get(service_config, "id", "") or "").strip()
        service_name = str(_cfg_get(service_config, "name", "") or service_id).strip()
        protocol = str(_cfg_get(service_config, "protocol", "http_rest") or "http_rest").strip().lower()

        if result is None:
            result = await run_connector(
                service_config,
                http_client=self._http_client,
                state_store=self._state_store,
            )

        ref_now = now or utc_now()
        now_iso = ref_now.isoformat()

        policy = _cfg_get(service_config, "alert_policy", None)
        policy_enabled = bool(_cfg_get(policy, "enabled", True)) if policy is not None else True
        alerting_enabled = bool(cfg.alerts.enabled) and policy_enabled

        policy_threshold = _cfg_get(policy, "consecutive_failures", None) if policy is not None else None
        threshold = max(
            1,
            int(
                policy_threshold
                if policy_threshold is not None
                else cfg.alerts.default_consecutive_failures
            ),
        )
        policy_cooldown = _cfg_get(policy, "cooldown_seconds", None) if policy is not None else None
        cooldown_seconds = max(
            0,
            int(
                policy_cooldown
                if policy_cooldown is not None
                else cfg.alerts.default_cooldown_seconds
            ),
        )

        async with self._get_service_lock(service_id):
            prev_state = await self._state_store.get_service_state(service_id)
            prev_status = prev_state["current_status"] if prev_state else "unknown"
            prev_failures = int(prev_state["consecutive_failures"]) if prev_state else 0
            last_transition_at = prev_state["last_transition_at"] if prev_state else None
            last_alert_at = prev_state["last_alert_at"] if prev_state else None
            muted_until = prev_state["muted_until"] if prev_state else None

            muted_dt = parse_iso_datetime(muted_until)
            is_muted = muted_dt is not None and muted_dt > ref_now

            incident_created: dict[str, Any] | None = None
            resolved_incidents: list[dict[str, Any]] = []
            delivery_results: list[dict[str, Any]] = []

            if result.ok and result.status == "up":
                new_status = "up"
                new_failures = 0
                last_error = None

                if prev_status != "up":
                    last_transition_at = now_iso
                    await self._bus.publish(
                        "service_status_changed",
                        {
                            "service_id": service_id,
                            "service_name": service_name,
                            "previous_status": prev_status,
                            "status": "up",
                            "latency_ms": result.latency_ms,
                            "message": result.message,
                            "metrics": result.metrics,
                        },
                    )

                open_incident = await self._state_store.get_open_incident(service_id)
                if open_incident is not None or prev_status == "down":
                    resolved_incidents = await self._state_store.resolve_open_incidents(
                        service_id, resolved_at=now_iso
                    )
                    if resolved_incidents or prev_status == "down":
                        resolved_id = (
                            resolved_incidents[0]["id"] if resolved_incidents else None
                        )
                        await self._bus.publish(
                            "alert_resolved",
                            {
                                "incident_id": resolved_id,
                                "service_id": service_id,
                                "service_name": service_name,
                                "status": "up",
                                "latency_ms": result.latency_ms,
                                "message": f"{service_name} est de nouveau opérationnel",
                                "resolved_at": now_iso,
                            },
                        )
                        if alerting_enabled and not is_muted and resolved_incidents:
                            notif = NotificationEvent(
                                event="alert_resolved",
                                title=f"✅ {service_name} rétabli",
                                message=f"Le service {service_name} est de nouveau en ligne.",
                                severity="info",
                                service_id=service_id,
                                service_name=service_name,
                                status="up",
                                latency_ms=result.latency_ms,
                                timestamp=now_iso,
                                incident_id=resolved_id,
                                details=result.message,
                            )
                            delivery_results = await self._dispatcher.dispatch_event(
                                notif, notifications_config=cfg.notifications
                            )
            else:
                awaiting_initial_webhook = (
                    protocol == "webhook_ingest"
                    and result.status == "degraded"
                    and "attente" in result.message.lower()
                )
                new_failures = prev_failures if awaiting_initial_webhook else prev_failures + 1
                last_error = result.message

                if result.status == "down" and new_failures >= threshold:
                    new_status = "down"
                elif prev_status == "down" and result.status == "down":
                    new_status = "down"
                else:
                    new_status = "degraded"

                if new_status != prev_status:
                    last_transition_at = now_iso
                    await self._bus.publish(
                        "service_status_changed",
                        {
                            "service_id": service_id,
                            "service_name": service_name,
                            "previous_status": prev_status,
                            "status": new_status,
                            "latency_ms": result.latency_ms,
                            "message": result.message,
                            "metrics": result.metrics,
                        },
                    )

                if new_status == "down" and new_failures >= threshold and alerting_enabled:
                    open_incident = await self._state_store.get_open_incident(service_id)
                    if open_incident is None:
                        incident_created = await self._state_store.create_incident(
                            service_id=service_id,
                            service_name=service_name,
                            severity="critical",
                            title=f"{service_name} hors ligne",
                            message=result.message or "Service injoignable",
                            started_at=now_iso,
                        )
                        active_incident = incident_created
                    else:
                        active_incident = open_incident

                    last_alert_dt = parse_iso_datetime(last_alert_at)
                    in_cooldown = (
                        last_alert_dt is not None
                        and cooldown_seconds > 0
                        and (ref_now - last_alert_dt).total_seconds() < cooldown_seconds
                    )

                    should_alert = (
                        prev_status != "down" or incident_created is not None
                    ) and not in_cooldown and not is_muted

                    if should_alert:
                        last_alert_at = now_iso
                        await self._bus.publish(
                            "alert_triggered",
                            {
                                "incident": active_incident,
                                "incident_id": active_incident["id"],
                                "service_id": service_id,
                                "service_name": service_name,
                                "severity": active_incident["severity"],
                                "status": "down",
                                "message": result.message,
                                "latency_ms": result.latency_ms,
                                "started_at": active_incident["started_at"],
                            },
                        )
                        notif = NotificationEvent(
                            event="alert_triggered",
                            title=f"🚨 {service_name} hors ligne",
                            message=result.message or f"Le service {service_name} ne répond plus.",
                            severity="critical",
                            service_id=service_id,
                            service_name=service_name,
                            status="down",
                            latency_ms=result.latency_ms,
                            timestamp=now_iso,
                            incident_id=active_incident["id"],
                            details=f"Échecs consécutifs : {new_failures}/{threshold}",
                        )
                        delivery_results = await self._dispatcher.dispatch_event(
                            notif, notifications_config=cfg.notifications
                        )

            state = await self._state_store.upsert_service_state(
                service_id,
                service_name=service_name,
                current_status=new_status,
                consecutive_failures=new_failures,
                last_check_at=now_iso,
                last_transition_at=last_transition_at,
                last_alert_at=last_alert_at,
                muted_until=muted_until,
                last_error=last_error,
                last_latency_ms=result.latency_ms,
                last_metrics=result.metrics,
            )

        return {
            "service_id": service_id,
            "result": result.to_dict(),
            "state": state,
            "incident_created": incident_created,
            "incidents_resolved": resolved_incidents,
            "notifications": delivery_results,
        }
