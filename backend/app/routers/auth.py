"""Authentication, HMAC session login, PIN management, and API bearer token CRUD."""

from __future__ import annotations

from collections import defaultdict, deque
import secrets
import time
from typing import Any
from uuid import uuid4

from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.config_manager import (
    create_session_token,
    get_config_manager,
    hash_pin,
    hash_token,
    verify_pin,
    verify_token_hash,
)
from app.config_schema import ApiTokenConfig, ApiTokenRole, utc_now_iso

router = APIRouter(prefix="/api", tags=["auth"])

_LOGIN_WINDOW_SECONDS = 60.0
_LOGIN_MAX_FAILURES = 10
_FAILED_ATTEMPTS: dict[str, deque[float]] = defaultdict(deque)


class LoginRequest(BaseModel):
    """Login request accepting either admin PIN or an API token."""

    pin: str | None = None
    api_token: str | None = None
    token: str | None = None


class CreateTokenRequest(BaseModel):
    """Create a new named Bearer API token."""

    name: str = Field(..., min_length=1, max_length=80)
    role: ApiTokenRole = "admin"


class UpdatePinRequest(BaseModel):
    """Set or rotate the numeric/alphanumeric admin PIN."""

    pin: str = Field(..., min_length=4, max_length=32)


def _require_admin(request: Request) -> dict[str, Any]:
    user = getattr(request.state, "user", None)
    if not isinstance(user, dict):
        raise HTTPException(status_code=401, detail="Authentification requise.")
    if user.get("role") != "admin":
        raise HTTPException(status_code=403, detail="Droits administrateur requis.")
    return user


def _check_rate_limit(client_key: str) -> None:
    now = time.monotonic()
    attempts = _FAILED_ATTEMPTS[client_key]
    while attempts and now - attempts[0] > _LOGIN_WINDOW_SECONDS:
        attempts.popleft()
    if len(attempts) >= _LOGIN_MAX_FAILURES:
        raise HTTPException(
            status_code=429,
            detail="Trop de tentatives de connexion échouées. Réessayez dans une minute.",
        )


def _record_failure(client_key: str) -> None:
    _FAILED_ATTEMPTS[client_key].append(time.monotonic())


def _clear_failures(client_key: str) -> None:
    _FAILED_ATTEMPTS.pop(client_key, None)


@router.get("/me")
async def get_current_user(request: Request) -> dict[str, Any]:
    """Return the authenticated Tailscale, Bearer token, or session identity."""
    return getattr(request.state, "user", {"login": "unknown", "name": "Unknown"})


@router.post("/auth/login")
async def login_with_pin_or_token(
    request: Request, payload: LoginRequest
) -> dict[str, Any]:
    """Authenticate with admin PIN or API token and return a signed HMAC session JWT."""
    client_key = request.client.host if request.client else "unknown"
    _check_rate_limit(client_key)

    manager = get_config_manager()
    cfg = manager.config
    security = cfg.security

    raw_token = (payload.api_token or payload.token or "").strip()
    if raw_token:
        for entry in security.api_tokens:
            if verify_token_hash(raw_token, entry.token_hash):
                _clear_failures(client_key)
                ttl = 86400
                session_jwt, expires_at = create_session_token(
                    subject=f"token:{entry.name}",
                    name=entry.name,
                    role=entry.role,
                    secret=manager.effective_session_secret,
                    ttl_seconds=ttl,
                )
                return {
                    "ok": True,
                    "access_token": session_jwt,
                    "token_type": "bearer",
                    "expires_in": ttl,
                    "expires_at": expires_at,
                    "user": {
                        "login": f"token:{entry.name}",
                        "name": entry.name,
                        "role": entry.role,
                        "auth_mode": "session",
                    },
                }

    raw_pin = (payload.pin or "").strip()
    if raw_pin and security.admin_pin_hash:
        if verify_pin(raw_pin, security.admin_pin_hash):
            _clear_failures(client_key)
            ttl = 86400
            owner = security.protected_owner_username or "admin"
            session_jwt, expires_at = create_session_token(
                subject=owner,
                name="Administrateur",
                role="admin",
                secret=manager.effective_session_secret,
                ttl_seconds=ttl,
            )
            return {
                "ok": True,
                "access_token": session_jwt,
                "token_type": "bearer",
                "expires_in": ttl,
                "expires_at": expires_at,
                "user": {
                    "login": owner,
                    "name": "Administrateur",
                    "role": "admin",
                    "auth_mode": "session",
                },
            }

    _record_failure(client_key)
    raise HTTPException(status_code=401, detail="PIN ou jeton API invalide.")


@router.get("/auth/tokens")
async def list_api_tokens(request: Request) -> dict[str, Any]:
    """List configured API token metadata without exposing token hashes."""
    _require_admin(request)
    cfg = get_config_manager().config
    return {
        "tokens": [
            {
                "id": tok.id,
                "name": tok.name,
                "role": tok.role,
                "created_at": tok.created_at,
            }
            for tok in cfg.security.api_tokens
        ]
    }


@router.post("/auth/tokens")
async def create_api_token(
    request: Request, payload: CreateTokenRequest
) -> dict[str, Any]:
    """Generate a new Bearer API token, store its SHA-256 hash in config.yaml, and return plaintext once."""
    _require_admin(request)
    manager = get_config_manager()
    security = manager.config.security.model_copy(deep=True)

    plaintext = f"pve_{secrets.token_urlsafe(32)}"
    entry = ApiTokenConfig(
        id=str(uuid4()),
        name=payload.name.strip(),
        token_hash=hash_token(plaintext),
        role=payload.role,
        created_at=utc_now_iso(),
    )
    security.api_tokens.append(entry)
    manager.update_section("security", security, source="token_create")

    return {
        "ok": True,
        "token": plaintext,
        "token_info": {
            "id": entry.id,
            "name": entry.name,
            "role": entry.role,
            "created_at": entry.created_at,
        },
    }


@router.delete("/auth/tokens/{token_id}")
async def revoke_api_token(request: Request, token_id: str) -> dict[str, Any]:
    """Revoke and delete a Bearer API token by ID from config.yaml."""
    _require_admin(request)
    manager = get_config_manager()
    security = manager.config.security.model_copy(deep=True)
    remaining = [t for t in security.api_tokens if t.id != token_id]
    if len(remaining) == len(security.api_tokens):
        raise HTTPException(status_code=404, detail=f"Jeton introuvable : {token_id}")
    security.api_tokens = remaining
    manager.update_section("security", security, source="token_revoke")
    return {"ok": True, "deleted_id": token_id}


@router.put("/auth/pin")
async def update_admin_pin(
    request: Request, payload: UpdatePinRequest
) -> dict[str, Any]:
    """Set or update the admin PIN hash stored in security.admin_pin_hash."""
    _require_admin(request)
    manager = get_config_manager()
    security = manager.config.security.model_copy(deep=True)
    security.admin_pin_hash = hash_pin(payload.pin.strip())
    manager.update_section("security", security, source="pin_update")
    return {"ok": True, "pin_configured": True}
