"""Incidents listing, acknowledgment, and per-service alert muting endpoints."""

from __future__ import annotations

from typing import Any

from fastapi import APIRouter, HTTPException, Query, Request, status
from pydantic import BaseModel, Field

from app.config_manager import get_config_manager
from app.services.realtime_bus import get_realtime_bus
from app.services.state_store import StateStore

router = APIRouter(prefix="/api/incidents", tags=["incidents"])


def _require_state_store(request: Request) -> StateStore:
    store = getattr(request.app.state, "state_store", None)
    if store is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="StateStore non initialisé",
        )
    return store


class MuteServicePayload(BaseModel):
    """Mute duration payload in minutes."""

    minutes: int = Field(default=60, ge=1, le=43200)


@router.get("")
async def list_incidents(
    request: Request,
    active_only: bool = Query(default=False),
    limit: int = Query(default=50, ge=1, le=500),
    service_id: str | None = Query(default=None),
) -> dict[str, Any]:
    """Return incident timeline and current per-service monitoring states."""
    store = _require_state_store(request)
    incidents = await store.list_incidents(
        active_only=active_only,
        limit=limit,
        service_id=service_id,
    )
    service_states = await store.list_service_states()
    active_count = sum(1 for item in incidents if item.get("resolved_at") is None)
    return {
        "incidents": incidents,
        "count": len(incidents),
        "active_count": active_count,
        "service_states": service_states,
    }


@router.post("/{incident_id}/ack")
async def acknowledge_incident(request: Request, incident_id: str) -> dict[str, Any]:
    """Acknowledge an incident so operators know it is being handled."""
    store = _require_state_store(request)
    incident = await store.acknowledge_incident(incident_id)
    if incident is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Incident introuvable : {incident_id}",
        )

    await get_realtime_bus().publish(
        "incident_acknowledged",
        {
            "incident_id": incident["id"],
            "service_id": incident["service_id"],
            "acknowledged_at": incident["acknowledged_at"],
            "incident": incident,
        },
    )
    return {"ok": True, "incident": incident}


@router.post("/services/{service_id}/mute")
async def mute_service_alerts(
    request: Request, service_id: str, payload: MuteServicePayload
) -> dict[str, Any]:
    """Temporarily mute alert notifications for a service."""
    store = _require_state_store(request)
    cfg = get_config_manager().config
    matched = next((s for s in cfg.custom_services if s.id == service_id), None)
    service_name = matched.name if matched else service_id

    state = await store.set_service_mute(
        service_id, minutes=payload.minutes, service_name=service_name
    )
    return {
        "ok": True,
        "service_id": service_id,
        "muted_until": state["muted_until"],
        "service_state": state,
    }


@router.delete("/services/{service_id}/mute")
async def unmute_service_alerts(request: Request, service_id: str) -> dict[str, Any]:
    """Clear an active mute window for a service."""
    store = _require_state_store(request)
    state = await store.clear_service_mute(service_id)
    return {
        "ok": True,
        "service_id": service_id,
        "muted_until": None,
        "service_state": state,
    }
