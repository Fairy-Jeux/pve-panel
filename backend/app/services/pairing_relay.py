"""Ephemeral PIN-based encrypted pairing relay between Apple TV and iPhone."""

from __future__ import annotations

from collections import deque
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
import hashlib
import re
import secrets
import time
from typing import Any
import uuid

_PIN_RE = re.compile(r"^\d{6}$")


class PairingError(Exception):
    """Base error for pairing relay operations."""


class PairingNotFoundError(PairingError):
    """Raised when a pairing PIN session does not exist or has expired."""


class PairingPendingError(PairingError):
    """Raised when a pairing session exists but has not been completed yet."""


class PairingAlreadyCompletedError(PairingError):
    """Raised when attempting to complete an already-completed pairing session."""


class PairingRateLimitError(PairingError):
    """Raised when too many failed PIN lookups occur from the same client."""

    def __init__(self, retry_after: int) -> None:
        super().__init__(f"Trop de tentatives de code PIN. Réessayez dans {retry_after}s.")
        self.retry_after = retry_after


@dataclass(slots=True)
class PairingSession:
    """In-memory ephemeral pairing session with 5-minute TTL."""

    pin: str
    session_id: str
    public_key: str
    device_name: str
    created_at: datetime
    expires_at: datetime
    completed: bool = False
    encrypted_payload: dict[str, str] | None = None


class PairingRelayStore:
    """In-memory TTL store for 6-digit PIN P-256 ECDH pairing sessions."""

    def __init__(
        self,
        *,
        ttl_seconds: int = 300,
        rate_limit_max_failures: int = 10,
        rate_limit_window_seconds: int = 60,
    ) -> None:
        self._ttl_seconds = max(30, int(ttl_seconds))
        self._max_failures = max(1, int(rate_limit_max_failures))
        self._window_seconds = max(10, int(rate_limit_window_seconds))
        self._sessions: dict[str, PairingSession] = {}
        self._failures: dict[str, deque[float]] = {}

    def _now_utc(self) -> datetime:
        return datetime.now(timezone.utc)

    def _purge_expired(self, now: datetime | None = None) -> None:
        ref = now or self._now_utc()
        expired_pins = [
            pin for pin, session in self._sessions.items() if session.expires_at <= ref
        ]
        for pin in expired_pins:
            self._sessions.pop(pin, None)

    def _check_rate_limit(self, client_key: str) -> None:
        now_mono = time.monotonic()
        cutoff = now_mono - self._window_seconds
        bucket = self._failures.get(client_key)
        if not bucket:
            return
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        if not bucket:
            self._failures.pop(client_key, None)
            return
        if len(bucket) >= self._max_failures:
            retry_after = max(1, int(round(bucket[0] + self._window_seconds - now_mono)))
            raise PairingRateLimitError(retry_after=retry_after)

    def _record_failure(self, client_key: str) -> None:
        now_mono = time.monotonic()
        cutoff = now_mono - self._window_seconds
        bucket = self._failures.setdefault(client_key, deque())
        while bucket and bucket[0] < cutoff:
            bucket.popleft()
        bucket.append(now_mono)

    def _generate_unique_pin(self) -> str:
        for _ in range(50):
            pin = f"{secrets.randbelow(1_000_000):06d}"
            if pin not in self._sessions:
                return pin
        # Fallback deterministic mix if collisions somehow happen
        digest = hashlib.sha256(uuid.uuid4().bytes).hexdigest()
        return f"{int(digest[:8], 16) % 1_000_000:06d}"

    def create_session(
        self,
        *,
        public_key: str,
        device_name: str = "Apple TV",
    ) -> dict[str, Any]:
        """Register a new receiver ephemeral P-256 session keyed by a 6-digit PIN."""
        clean_key = public_key.strip()
        if not clean_key:
            raise ValueError("public_key est requis")

        now = self._now_utc()
        self._purge_expired(now)

        pin = self._generate_unique_pin()
        session_id = uuid.uuid4().hex
        expires_at = now + timedelta(seconds=self._ttl_seconds)
        session = PairingSession(
            pin=pin,
            session_id=session_id,
            public_key=clean_key,
            device_name=device_name.strip() or "Apple TV",
            created_at=now,
            expires_at=expires_at,
        )
        self._sessions[pin] = session
        return {
            "pin": pin,
            "session_id": session_id,
            "expires_at": expires_at.isoformat(),
            "ttl_seconds": self._ttl_seconds,
        }

    def get_session(self, pin: str, *, client_key: str = "global") -> dict[str, Any]:
        """Fetch receiver public key and device name for a valid PIN."""
        self._check_rate_limit(client_key)
        now = self._now_utc()
        self._purge_expired(now)

        clean_pin = pin.strip()
        session = self._sessions.get(clean_pin) if _PIN_RE.match(clean_pin) else None
        if session is None:
            self._record_failure(client_key)
            raise PairingNotFoundError("Session d'appairage introuvable ou expirée")

        return {
            "session_id": session.session_id,
            "pin": session.pin,
            "public_key": session.public_key,
            "device_name": session.device_name,
            "expires_at": session.expires_at.isoformat(),
            "completed": session.completed,
        }

    def complete_session(
        self,
        pin: str,
        *,
        sender_public_key: str,
        nonce: str,
        ciphertext: str,
        tag: str,
        client_key: str = "global",
    ) -> dict[str, Any]:
        """Store the sender's encrypted pairing bundle for one-time retrieval."""
        self._check_rate_limit(client_key)
        now = self._now_utc()
        self._purge_expired(now)

        clean_pin = pin.strip()
        session = self._sessions.get(clean_pin) if _PIN_RE.match(clean_pin) else None
        if session is None:
            self._record_failure(client_key)
            raise PairingNotFoundError("Session d'appairage introuvable ou expirée")

        if session.completed:
            raise PairingAlreadyCompletedError(
                "Cette session d'appairage a déjà été complétée"
            )

        session.encrypted_payload = {
            "sender_public_key": sender_public_key.strip(),
            "nonce": nonce.strip(),
            "ciphertext": ciphertext.strip(),
            "tag": tag.strip(),
        }
        session.completed = True
        return {
            "ok": True,
            "session_id": session.session_id,
            "pin": session.pin,
            "device_name": session.device_name,
            "completed": True,
        }

    def consume_payload(
        self, pin: str, *, client_key: str = "global"
    ) -> dict[str, Any]:
        """Retrieve the encrypted pairing blob once and immediately clear the session."""
        self._check_rate_limit(client_key)
        now = self._now_utc()
        self._purge_expired(now)

        clean_pin = pin.strip()
        session = self._sessions.get(clean_pin) if _PIN_RE.match(clean_pin) else None
        if session is None:
            self._record_failure(client_key)
            raise PairingNotFoundError("Session d'appairage introuvable ou expirée")

        if not session.completed or session.encrypted_payload is None:
            raise PairingPendingError("Appairage en attente de validation")

        payload = dict(session.encrypted_payload)
        session_id = session.session_id
        self._sessions.pop(clean_pin, None)
        return {
            "session_id": session_id,
            "pin": clean_pin,
            **payload,
        }

    @property
    def active_count(self) -> int:
        """Return number of currently active (non-expired) sessions."""
        self._purge_expired()
        return len(self._sessions)
