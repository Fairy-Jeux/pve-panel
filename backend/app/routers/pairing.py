"""Encrypted PIN-based pairing relay endpoints between Apple TV and iPhone."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field

from app.services.pairing_relay import (
    PairingAlreadyCompletedError,
    PairingNotFoundError,
    PairingPendingError,
    PairingRateLimitError,
    PairingRelayStore,
)
from app.services.realtime_bus import get_realtime_bus

router = APIRouter(prefix="/api/pairing", tags=["pairing"])

_fallback_relay_store = PairingRelayStore()


def _get_relay(request: Request) -> PairingRelayStore:
    relay = getattr(request.app.state, "pairing_relay", None)
    return relay if isinstance(relay, PairingRelayStore) else _fallback_relay_store


def _client_key(request: Request) -> str:
    forwarded = request.headers.get("x-forwarded-for", "").split(",")[0].strip()
    if forwarded:
        return forwarded
    if request.client and request.client.host:
        return request.client.host
    return "unknown"


class CreatePairingSessionPayload(BaseModel):
    """Apple TV receiver initiates a 5-minute PIN session with its P-256 public key."""

    model_config = ConfigDict(extra="ignore")

    public_key: str = Field(..., min_length=16, max_length=2048)
    device_name: str = Field(default="Apple TV", min_length=1, max_length=128)


class CompletePairingPayload(BaseModel):
    """iPhone sender posts its ephemeral P-256 public key and AES-GCM encrypted bundle."""

    model_config = ConfigDict(extra="ignore")

    sender_public_key: str = Field(..., min_length=16, max_length=2048)
    nonce: str = Field(..., min_length=8, max_length=512)
    ciphertext: str = Field(..., min_length=4, max_length=65536)
    tag: str = Field(..., min_length=8, max_length=512)


@router.post("/sessions", status_code=status.HTTP_201_CREATED)
async def create_pairing_session(
    request: Request, payload: CreatePairingSessionPayload
) -> dict[str, Any]:
    """Create a 6-digit PIN pairing session with 5-minute TTL."""
    relay = _get_relay(request)
    try:
        return relay.create_session(
            public_key=payload.public_key,
            device_name=payload.device_name,
        )
    except ValueError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc


@router.get("/sessions/{pin}")
async def get_pairing_session(request: Request, pin: str) -> dict[str, Any]:
    """Fetch receiver ephemeral public key and device name for a 6-digit PIN."""
    relay = _get_relay(request)
    try:
        return relay.get_session(pin, client_key=_client_key(request))
    except PairingRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc
    except PairingNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc


@router.post("/sessions/{pin}/complete")
async def complete_pairing_session(
    request: Request, pin: str, payload: CompletePairingPayload
) -> dict[str, Any]:
    """Store encrypted pairing bundle from iPhone and notify Apple TV over RealtimeBus."""
    relay = _get_relay(request)
    try:
        result = relay.complete_session(
            pin,
            sender_public_key=payload.sender_public_key,
            nonce=payload.nonce,
            ciphertext=payload.ciphertext,
            tag=payload.tag,
            client_key=_client_key(request),
        )
    except PairingRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc
    except PairingNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except PairingAlreadyCompletedError as exc:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT, detail=str(exc)
        ) from exc

    await get_realtime_bus().publish(
        "pairing_completed",
        {
            "pin": result["pin"],
            "session_id": result["session_id"],
            "device_name": result["device_name"],
        },
    )
    return {
        "ok": True,
        "session_id": result["session_id"],
        "pin": result["pin"],
        "completed": True,
    }


@router.get("/sessions/{pin}/payload")
async def consume_pairing_payload(request: Request, pin: str) -> dict[str, Any]:
    """Retrieve the encrypted pairing payload once and clear the ephemeral session."""
    relay = _get_relay(request)
    try:
        return relay.consume_payload(pin, client_key=_client_key(request))
    except PairingRateLimitError as exc:
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=str(exc),
            headers={"Retry-After": str(exc.retry_after)},
        ) from exc
    except PairingNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except PairingPendingError as exc:
        raise HTTPException(
            status_code=status.HTTP_425_TOO_EARLY, detail=str(exc)
        ) from exc
