"""SQLite persistence for service states, incidents, webhook heartbeats, and APNs devices."""

from __future__ import annotations

import asyncio
from datetime import datetime, timedelta, timezone
import json
import os
from pathlib import Path
import sqlite3
import threading
from typing import Any
import uuid


def resolve_state_db_path(explicit_path: str | Path | None = None) -> Path:
    """Resolve SQLite state DB path via ConfigManager path rules or an explicit override."""
    if explicit_path is not None:
        raw = str(explicit_path)
        return Path(raw) if raw != ":memory:" else Path(":memory:")

    try:
        from app.config_manager import resolve_state_db_path as _cm_resolve_state_db_path

        return _cm_resolve_state_db_path()
    except Exception:
        pass

    env_path = os.environ.get("STATE_DB_PATH", "").strip()
    if env_path:
        return Path(env_path)

    if Path("/app/config").is_dir() or Path("/app").is_dir():
        return Path("/app/config/state.db")

    repo_root = Path(__file__).resolve().parents[3]
    return repo_root / "config" / "state.db"


def utc_now() -> datetime:
    """Return current UTC datetime."""
    return datetime.now(timezone.utc)


def utc_now_iso() -> str:
    """Return current UTC ISO-8601 timestamp string."""
    return utc_now().isoformat()


def parse_iso_datetime(value: str | None) -> datetime | None:
    """Parse an ISO-8601 string into a timezone-aware UTC datetime."""
    if not value:
        return None
    raw = value.strip()
    if not raw:
        return None
    if raw.endswith("Z"):
        raw = f"{raw[:-1]}+00:00"
    try:
        dt = datetime.fromisoformat(raw)
    except ValueError:
        return None
    if dt.tzinfo is None:
        return dt.replace(tzinfo=timezone.utc)
    return dt.astimezone(timezone.utc)


class StateStore:
    """Thread-safe async wrapper around SQLite persistence for alerting and devices."""

    def __init__(self, db_path: str | Path | None = None) -> None:
        self._explicit_path = db_path
        self._db_path = resolve_state_db_path(db_path)
        self._lock = threading.RLock()
        self._conn: sqlite3.Connection | None = None

    @property
    def db_path(self) -> Path:
        """Return resolved database path."""
        return self._db_path

    def _ensure_conn_sync(self) -> sqlite3.Connection:
        with self._lock:
            if self._conn is not None:
                return self._conn

            is_memory = str(self._db_path) == ":memory:"
            if not is_memory:
                self._db_path.parent.mkdir(parents=True, exist_ok=True)

            conn = sqlite3.connect(
                str(self._db_path),
                timeout=10.0,
                check_same_thread=False,
            )
            conn.row_factory = sqlite3.Row
            if not is_memory:
                conn.execute("PRAGMA journal_mode=WAL")
            conn.execute("PRAGMA synchronous=NORMAL")
            conn.execute("PRAGMA foreign_keys=ON")
            self._init_schema_sync(conn)
            self._conn = conn
            return conn

    @staticmethod
    def _init_schema_sync(conn: sqlite3.Connection) -> None:
        conn.executescript(
            """
            CREATE TABLE IF NOT EXISTS service_states (
                service_id TEXT PRIMARY KEY,
                service_name TEXT NOT NULL DEFAULT '',
                current_status TEXT NOT NULL DEFAULT 'unknown',
                consecutive_failures INTEGER NOT NULL DEFAULT 0,
                last_check_at TEXT,
                last_transition_at TEXT,
                last_alert_at TEXT,
                muted_until TEXT,
                last_error TEXT,
                last_latency_ms INTEGER,
                last_metrics_json TEXT NOT NULL DEFAULT '{}'
            );

            CREATE TABLE IF NOT EXISTS incidents (
                id TEXT PRIMARY KEY,
                service_id TEXT NOT NULL,
                service_name TEXT NOT NULL,
                severity TEXT NOT NULL,
                title TEXT NOT NULL,
                message TEXT NOT NULL,
                started_at TEXT NOT NULL,
                resolved_at TEXT,
                acknowledged INTEGER NOT NULL DEFAULT 0,
                acknowledged_at TEXT
            );

            CREATE INDEX IF NOT EXISTS idx_incidents_service_resolved
                ON incidents (service_id, resolved_at);
            CREATE INDEX IF NOT EXISTS idx_incidents_started_at
                ON incidents (started_at DESC);

            CREATE TABLE IF NOT EXISTS apns_devices (
                device_token TEXT PRIMARY KEY,
                platform TEXT NOT NULL DEFAULT 'ios',
                device_name TEXT NOT NULL DEFAULT '',
                app_version TEXT NOT NULL DEFAULT '',
                environment TEXT NOT NULL DEFAULT 'production',
                updated_at TEXT NOT NULL
            );

            CREATE TABLE IF NOT EXISTS webhook_heartbeats (
                service_id TEXT PRIMARY KEY,
                status TEXT NOT NULL DEFAULT 'up',
                message TEXT NOT NULL DEFAULT '',
                metrics_json TEXT NOT NULL DEFAULT '{}',
                received_at TEXT NOT NULL,
                ttl_seconds INTEGER NOT NULL DEFAULT 300
            );
            """
        )
        cols = {
            row["name"]
            for row in conn.execute("PRAGMA table_info(service_states)").fetchall()
        }
        if "last_metrics_json" not in cols:
            conn.execute(
                "ALTER TABLE service_states ADD COLUMN last_metrics_json TEXT NOT NULL DEFAULT '{}'"
            )
        conn.commit()

    async def initialize(self) -> None:
        """Open SQLite connection and ensure schema exists."""
        await asyncio.to_thread(self._ensure_conn_sync)

    def _close_sync(self) -> None:
        with self._lock:
            if self._conn is not None:
                self._conn.close()
                self._conn = None

    async def close(self) -> None:
        """Close the SQLite database connection."""
        await asyncio.to_thread(self._close_sync)

    @staticmethod
    def _row_to_service_state(row: sqlite3.Row) -> dict[str, Any]:
        raw_metrics = row["last_metrics_json"] or "{}"
        try:
            metrics = json.loads(raw_metrics)
            if not isinstance(metrics, dict):
                metrics = {}
        except Exception:
            metrics = {}
        return {
            "service_id": row["service_id"],
            "service_name": row["service_name"],
            "current_status": row["current_status"],
            "consecutive_failures": int(row["consecutive_failures"] or 0),
            "last_check_at": row["last_check_at"],
            "last_transition_at": row["last_transition_at"],
            "last_alert_at": row["last_alert_at"],
            "muted_until": row["muted_until"],
            "last_error": row["last_error"],
            "last_latency_ms": row["last_latency_ms"],
            "last_metrics": metrics,
        }

    @staticmethod
    def _row_to_incident(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "id": row["id"],
            "service_id": row["service_id"],
            "service_name": row["service_name"],
            "severity": row["severity"],
            "title": row["title"],
            "message": row["message"],
            "started_at": row["started_at"],
            "resolved_at": row["resolved_at"],
            "acknowledged": bool(row["acknowledged"]),
            "acknowledged_at": row["acknowledged_at"],
        }

    @staticmethod
    def _row_to_apns_device(row: sqlite3.Row) -> dict[str, Any]:
        return {
            "device_token": row["device_token"],
            "platform": row["platform"],
            "device_name": row["device_name"],
            "app_version": row["app_version"],
            "environment": row["environment"],
            "updated_at": row["updated_at"],
        }

    # --- Service States ---

    def _get_service_state_sync(self, service_id: str) -> dict[str, Any] | None:
        with self._lock:
            conn = self._ensure_conn_sync()
            row = conn.execute(
                "SELECT * FROM service_states WHERE service_id = ?",
                (service_id,),
            ).fetchone()
            return self._row_to_service_state(row) if row is not None else None

    async def get_service_state(self, service_id: str) -> dict[str, Any] | None:
        """Fetch stored state for a single service."""
        return await asyncio.to_thread(self._get_service_state_sync, service_id)

    def _list_service_states_sync(self) -> list[dict[str, Any]]:
        with self._lock:
            conn = self._ensure_conn_sync()
            rows = conn.execute(
                "SELECT * FROM service_states ORDER BY service_id ASC"
            ).fetchall()
            return [self._row_to_service_state(row) for row in rows]

    async def list_service_states(self) -> list[dict[str, Any]]:
        """Return all persisted service states."""
        return await asyncio.to_thread(self._list_service_states_sync)

    def _upsert_service_state_sync(
        self,
        service_id: str,
        *,
        service_name: str,
        current_status: str,
        consecutive_failures: int,
        last_check_at: str | None,
        last_transition_at: str | None,
        last_alert_at: str | None,
        muted_until: str | None,
        last_error: str | None,
        last_latency_ms: int | None,
        last_metrics: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        metrics_json = json.dumps(last_metrics or {}, ensure_ascii=False)
        with self._lock:
            conn = self._ensure_conn_sync()
            conn.execute(
                """
                INSERT INTO service_states (
                    service_id, service_name, current_status, consecutive_failures,
                    last_check_at, last_transition_at, last_alert_at, muted_until,
                    last_error, last_latency_ms, last_metrics_json
                )
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
                ON CONFLICT(service_id) DO UPDATE SET
                    service_name = excluded.service_name,
                    current_status = excluded.current_status,
                    consecutive_failures = excluded.consecutive_failures,
                    last_check_at = excluded.last_check_at,
                    last_transition_at = excluded.last_transition_at,
                    last_alert_at = excluded.last_alert_at,
                    muted_until = excluded.muted_until,
                    last_error = excluded.last_error,
                    last_latency_ms = excluded.last_latency_ms,
                    last_metrics_json = excluded.last_metrics_json
                """,
                (
                    service_id,
                    service_name,
                    current_status,
                    int(consecutive_failures),
                    last_check_at,
                    last_transition_at,
                    last_alert_at,
                    muted_until,
                    last_error,
                    last_latency_ms,
                    metrics_json,
                ),
            )
            conn.commit()
            row = conn.execute(
                "SELECT * FROM service_states WHERE service_id = ?",
                (service_id,),
            ).fetchone()
            assert row is not None
            return self._row_to_service_state(row)

    async def upsert_service_state(
        self,
        service_id: str,
        *,
        service_name: str,
        current_status: str,
        consecutive_failures: int,
        last_check_at: str | None,
        last_transition_at: str | None,
        last_alert_at: str | None,
        muted_until: str | None,
        last_error: str | None,
        last_latency_ms: int | None,
        last_metrics: dict[str, Any] | None = None,
    ) -> dict[str, Any]:
        """Insert or update a service's monitoring state."""
        return await asyncio.to_thread(
            self._upsert_service_state_sync,
            service_id,
            service_name=service_name,
            current_status=current_status,
            consecutive_failures=consecutive_failures,
            last_check_at=last_check_at,
            last_transition_at=last_transition_at,
            last_alert_at=last_alert_at,
            muted_until=muted_until,
            last_error=last_error,
            last_latency_ms=last_latency_ms,
            last_metrics=last_metrics,
        )

    def _set_service_mute_sync(
        self, service_id: str, minutes: int, service_name: str | None = None
    ) -> dict[str, Any]:
        muted_until = (utc_now() + timedelta(minutes=max(1, int(minutes)))).isoformat()
        with self._lock:
            conn = self._ensure_conn_sync()
            existing = conn.execute(
                "SELECT * FROM service_states WHERE service_id = ?",
                (service_id,),
            ).fetchone()
            if existing is None:
                conn.execute(
                    """
                    INSERT INTO service_states (
                        service_id, service_name, current_status, consecutive_failures, muted_until
                    ) VALUES (?, ?, 'unknown', 0, ?)
                    """,
                    (service_id, service_name or service_id, muted_until),
                )
            else:
                conn.execute(
                    "UPDATE service_states SET muted_until = ? WHERE service_id = ?",
                    (muted_until, service_id),
                )
            conn.commit()
            row = conn.execute(
                "SELECT * FROM service_states WHERE service_id = ?",
                (service_id,),
            ).fetchone()
            assert row is not None
            return self._row_to_service_state(row)

    async def set_service_mute(
        self, service_id: str, minutes: int, service_name: str | None = None
    ) -> dict[str, Any]:
        """Mute alert notifications for a service for the given duration in minutes."""
        return await asyncio.to_thread(
            self._set_service_mute_sync, service_id, minutes, service_name
        )

    def _clear_service_mute_sync(self, service_id: str) -> dict[str, Any] | None:
        with self._lock:
            conn = self._ensure_conn_sync()
            conn.execute(
                "UPDATE service_states SET muted_until = NULL WHERE service_id = ?",
                (service_id,),
            )
            conn.commit()
            row = conn.execute(
                "SELECT * FROM service_states WHERE service_id = ?",
                (service_id,),
            ).fetchone()
            return self._row_to_service_state(row) if row is not None else None

    async def clear_service_mute(self, service_id: str) -> dict[str, Any] | None:
        """Remove any active mute window for a service."""
        return await asyncio.to_thread(self._clear_service_mute_sync, service_id)

    async def is_service_muted(
        self, service_id: str, now: datetime | None = None
    ) -> bool:
        """Return True if the service currently has an active muted_until timestamp."""
        state = await self.get_service_state(service_id)
        if not state:
            return False
        muted_until = parse_iso_datetime(state.get("muted_until"))
        if muted_until is None:
            return False
        ref_now = now or utc_now()
        return muted_until > ref_now

    # --- Webhook Heartbeats ---

    def _record_webhook_heartbeat_sync(
        self,
        service_id: str,
        *,
        status: str = "up",
        message: str = "Webhook heartbeat received",
        metrics: dict[str, Any] | None = None,
        ttl_seconds: int = 300,
        received_at: str | None = None,
    ) -> dict[str, Any]:
        ts = received_at or utc_now_iso()
        metrics_json = json.dumps(metrics or {}, ensure_ascii=False)
        with self._lock:
            conn = self._ensure_conn_sync()
            conn.execute(
                """
                INSERT INTO webhook_heartbeats (
                    service_id, status, message, metrics_json, received_at, ttl_seconds
                )
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(service_id) DO UPDATE SET
                    status = excluded.status,
                    message = excluded.message,
                    metrics_json = excluded.metrics_json,
                    received_at = excluded.received_at,
                    ttl_seconds = excluded.ttl_seconds
                """,
                (service_id, status, message, metrics_json, ts, int(ttl_seconds)),
            )
            conn.commit()
            return {
                "service_id": service_id,
                "status": status,
                "message": message,
                "metrics": metrics or {},
                "received_at": ts,
                "ttl_seconds": int(ttl_seconds),
            }

    async def record_webhook_heartbeat(
        self,
        service_id: str,
        *,
        status: str = "up",
        message: str = "Webhook heartbeat received",
        metrics: dict[str, Any] | None = None,
        ttl_seconds: int = 300,
        received_at: str | None = None,
    ) -> dict[str, Any]:
        """Store or update the latest push webhook heartbeat for a service."""
        return await asyncio.to_thread(
            self._record_webhook_heartbeat_sync,
            service_id,
            status=status,
            message=message,
            metrics=metrics,
            ttl_seconds=ttl_seconds,
            received_at=received_at,
        )

    def _get_webhook_heartbeat_sync(self, service_id: str) -> dict[str, Any] | None:
        with self._lock:
            conn = self._ensure_conn_sync()
            row = conn.execute(
                "SELECT * FROM webhook_heartbeats WHERE service_id = ?",
                (service_id,),
            ).fetchone()
            if row is None:
                return None
            try:
                metrics = json.loads(row["metrics_json"] or "{}")
                if not isinstance(metrics, dict):
                    metrics = {}
            except Exception:
                metrics = {}
            return {
                "service_id": row["service_id"],
                "status": row["status"],
                "message": row["message"],
                "metrics": metrics,
                "received_at": row["received_at"],
                "ttl_seconds": int(row["ttl_seconds"]),
            }

    async def get_webhook_heartbeat(self, service_id: str) -> dict[str, Any] | None:
        """Retrieve the latest webhook heartbeat record for a service."""
        return await asyncio.to_thread(self._get_webhook_heartbeat_sync, service_id)

    # --- Incidents ---

    def _create_incident_sync(
        self,
        *,
        service_id: str,
        service_name: str,
        severity: str,
        title: str,
        message: str,
        started_at: str | None = None,
    ) -> dict[str, Any]:
        incident_id = uuid.uuid4().hex
        ts = started_at or utc_now_iso()
        with self._lock:
            conn = self._ensure_conn_sync()
            conn.execute(
                """
                INSERT INTO incidents (
                    id, service_id, service_name, severity, title, message,
                    started_at, resolved_at, acknowledged, acknowledged_at
                ) VALUES (?, ?, ?, ?, ?, ?, ?, NULL, 0, NULL)
                """,
                (incident_id, service_id, service_name, severity, title, message, ts),
            )
            conn.commit()
            row = conn.execute(
                "SELECT * FROM incidents WHERE id = ?", (incident_id,)
            ).fetchone()
            assert row is not None
            return self._row_to_incident(row)

    async def create_incident(
        self,
        *,
        service_id: str,
        service_name: str,
        severity: str,
        title: str,
        message: str,
        started_at: str | None = None,
    ) -> dict[str, Any]:
        """Create and persist a new incident."""
        return await asyncio.to_thread(
            self._create_incident_sync,
            service_id=service_id,
            service_name=service_name,
            severity=severity,
            title=title,
            message=message,
            started_at=started_at,
        )

    def _get_incident_sync(self, incident_id: str) -> dict[str, Any] | None:
        with self._lock:
            conn = self._ensure_conn_sync()
            row = conn.execute(
                "SELECT * FROM incidents WHERE id = ?", (incident_id,)
            ).fetchone()
            return self._row_to_incident(row) if row is not None else None

    async def get_incident(self, incident_id: str) -> dict[str, Any] | None:
        """Return a single incident by ID."""
        return await asyncio.to_thread(self._get_incident_sync, incident_id)

    def _get_open_incident_sync(self, service_id: str) -> dict[str, Any] | None:
        with self._lock:
            conn = self._ensure_conn_sync()
            row = conn.execute(
                """
                SELECT * FROM incidents
                WHERE service_id = ? AND resolved_at IS NULL
                ORDER BY started_at DESC
                LIMIT 1
                """,
                (service_id,),
            ).fetchone()
            return self._row_to_incident(row) if row is not None else None

    async def get_open_incident(self, service_id: str) -> dict[str, Any] | None:
        """Return the active (unresolved) incident for a service, if any."""
        return await asyncio.to_thread(self._get_open_incident_sync, service_id)

    def _list_incidents_sync(
        self,
        *,
        active_only: bool = False,
        limit: int = 50,
        service_id: str | None = None,
    ) -> list[dict[str, Any]]:
        clauses: list[str] = []
        params: list[Any] = []
        if active_only:
            clauses.append("resolved_at IS NULL")
        if service_id:
            clauses.append("service_id = ?")
            params.append(service_id)
        where = f"WHERE {' AND '.join(clauses)}" if clauses else ""
        safe_limit = max(1, min(int(limit), 500))
        params.append(safe_limit)
        with self._lock:
            conn = self._ensure_conn_sync()
            rows = conn.execute(
                f"SELECT * FROM incidents {where} ORDER BY started_at DESC LIMIT ?",
                tuple(params),
            ).fetchall()
            return [self._row_to_incident(row) for row in rows]

    async def list_incidents(
        self,
        *,
        active_only: bool = False,
        limit: int = 50,
        service_id: str | None = None,
    ) -> list[dict[str, Any]]:
        """List incidents sorted newest first."""
        return await asyncio.to_thread(
            self._list_incidents_sync,
            active_only=active_only,
            limit=limit,
            service_id=service_id,
        )

    def _resolve_open_incidents_sync(
        self, service_id: str, resolved_at: str | None = None
    ) -> list[dict[str, Any]]:
        ts = resolved_at or utc_now_iso()
        with self._lock:
            conn = self._ensure_conn_sync()
            open_rows = conn.execute(
                "SELECT id FROM incidents WHERE service_id = ? AND resolved_at IS NULL",
                (service_id,),
            ).fetchall()
            if not open_rows:
                return []
            ids = [row["id"] for row in open_rows]
            conn.execute(
                "UPDATE incidents SET resolved_at = ? WHERE service_id = ? AND resolved_at IS NULL",
                (ts, service_id),
            )
            conn.commit()
            placeholders = ",".join("?" for _ in ids)
            updated = conn.execute(
                f"SELECT * FROM incidents WHERE id IN ({placeholders}) ORDER BY started_at DESC",
                tuple(ids),
            ).fetchall()
            return [self._row_to_incident(row) for row in updated]

    async def resolve_open_incidents(
        self, service_id: str, resolved_at: str | None = None
    ) -> list[dict[str, Any]]:
        """Mark all open incidents for a service as resolved and return them."""
        return await asyncio.to_thread(
            self._resolve_open_incidents_sync, service_id, resolved_at
        )

    def _acknowledge_incident_sync(self, incident_id: str) -> dict[str, Any] | None:
        ts = utc_now_iso()
        with self._lock:
            conn = self._ensure_conn_sync()
            row = conn.execute(
                "SELECT * FROM incidents WHERE id = ?", (incident_id,)
            ).fetchone()
            if row is None:
                return None
            if not bool(row["acknowledged"]):
                conn.execute(
                    "UPDATE incidents SET acknowledged = 1, acknowledged_at = ? WHERE id = ?",
                    (ts, incident_id),
                )
                conn.commit()
                row = conn.execute(
                    "SELECT * FROM incidents WHERE id = ?", (incident_id,)
                ).fetchone()
            assert row is not None
            return self._row_to_incident(row)

    async def acknowledge_incident(self, incident_id: str) -> dict[str, Any] | None:
        """Mark an incident as acknowledged."""
        return await asyncio.to_thread(self._acknowledge_incident_sync, incident_id)

    # --- APNs Devices ---

    def _upsert_apns_device_sync(
        self,
        *,
        device_token: str,
        platform: str = "ios",
        device_name: str = "",
        app_version: str = "",
        environment: str = "production",
    ) -> dict[str, Any]:
        ts = utc_now_iso()
        norm_token = device_token.strip().replace(" ", "").lower()
        norm_env = "sandbox" if environment.strip().lower() == "sandbox" else "production"
        with self._lock:
            conn = self._ensure_conn_sync()
            conn.execute(
                """
                INSERT INTO apns_devices (
                    device_token, platform, device_name, app_version, environment, updated_at
                )
                VALUES (?, ?, ?, ?, ?, ?)
                ON CONFLICT(device_token) DO UPDATE SET
                    platform = excluded.platform,
                    device_name = excluded.device_name,
                    app_version = excluded.app_version,
                    environment = excluded.environment,
                    updated_at = excluded.updated_at
                """,
                (
                    norm_token,
                    platform.strip().lower() or "ios",
                    device_name.strip(),
                    app_version.strip(),
                    norm_env,
                    ts,
                ),
            )
            conn.commit()
            row = conn.execute(
                "SELECT * FROM apns_devices WHERE device_token = ?", (norm_token,)
            ).fetchone()
            assert row is not None
            return self._row_to_apns_device(row)

    async def upsert_apns_device(
        self,
        *,
        device_token: str,
        platform: str = "ios",
        device_name: str = "",
        app_version: str = "",
        environment: str = "production",
    ) -> dict[str, Any]:
        """Register or update an APNs device token."""
        return await asyncio.to_thread(
            self._upsert_apns_device_sync,
            device_token=device_token,
            platform=platform,
            device_name=device_name,
            app_version=app_version,
            environment=environment,
        )

    def _delete_apns_device_sync(self, device_token: str) -> bool:
        norm_token = device_token.strip().replace(" ", "").lower()
        with self._lock:
            conn = self._ensure_conn_sync()
            cur = conn.execute(
                "DELETE FROM apns_devices WHERE device_token = ?", (norm_token,)
            )
            conn.commit()
            return cur.rowcount > 0

    async def delete_apns_device(self, device_token: str) -> bool:
        """Unregister an APNs device token."""
        return await asyncio.to_thread(self._delete_apns_device_sync, device_token)

    def _list_apns_devices_sync(
        self, environment: str | None = None
    ) -> list[dict[str, Any]]:
        with self._lock:
            conn = self._ensure_conn_sync()
            if environment:
                rows = conn.execute(
                    "SELECT * FROM apns_devices WHERE environment = ? ORDER BY updated_at DESC",
                    (environment.strip().lower(),),
                ).fetchall()
            else:
                rows = conn.execute(
                    "SELECT * FROM apns_devices ORDER BY updated_at DESC"
                ).fetchall()
            return [self._row_to_apns_device(row) for row in rows]

    async def list_apns_devices(
        self, environment: str | None = None
    ) -> list[dict[str, Any]]:
        """Return registered APNs devices."""
        return await asyncio.to_thread(self._list_apns_devices_sync, environment)
