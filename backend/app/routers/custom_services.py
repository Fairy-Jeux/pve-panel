"""CRUD, reordering, live dry-run testing, and webhook ingest for custom services."""

from __future__ import annotations

import hmac
import re
from typing import Any

from fastapi import APIRouter, Body, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field, model_validator

from app.config_manager import get_config_manager
from app.config_schema import (
    AlertPolicyConfig,
    CustomServiceConfig,
    ServiceAuthType,
    ServiceProtocol,
    is_masked_or_empty,
    is_secret_configured,
)
from app.services.connectors import ConnectorResult, run_connector
from app.services.media_clients import check_custom_services, serialize_custom_service
from app.services.state_store import StateStore

router = APIRouter(prefix="/api/custom-services", tags=["custom-services"])


def _get_state_store(request: Request) -> StateStore | None:
    return getattr(request.app.state, "state_store", None)


def _slugify_id(name: str, existing_ids: set[str]) -> str:
    base = re.sub(r"[^a-z0-9]+", "-", name.strip().lower()).strip("-") or "service"
    candidate = base
    suffix = 2
    while candidate in existing_ids:
        candidate = f"{base}-{suffix}"
        suffix += 1
    return candidate


class CustomServiceCreatePayload(BaseModel):
    """Payload to create a new custom service persisted in config.yaml."""

    model_config = ConfigDict(extra="ignore")

    id: str = ""
    name: str = Field(..., min_length=1)
    description: str = ""
    category: str = "Services"
    icon: str = "Globe"
    protocol: ServiceProtocol = "http_rest"
    host: str = ""
    port: int | None = Field(default=None, ge=1, le=65535)
    url: str = ""
    health_url: str = ""
    internal_url: str = ""
    auth_type: ServiceAuthType = "none"
    auth_token: str = ""
    auth_header_name: str = ""
    json_metric_path: str = ""
    expected_status: int = Field(default=200, ge=100, le=599)
    refresh_interval_seconds: int = Field(default=30, ge=5, le=3600)
    order: int | None = None
    enabled: bool = True
    verify_ssl: bool = False
    webhook_ttl_seconds: int = Field(default=300, ge=10, le=86400)
    alert_policy: AlertPolicyConfig = Field(default_factory=AlertPolicyConfig)


class CustomServiceUpdatePayload(BaseModel):
    """Partial or full update payload for an existing custom service."""

    model_config = ConfigDict(extra="ignore")

    name: str | None = Field(default=None, min_length=1)
    description: str | None = None
    category: str | None = None
    icon: str | None = None
    protocol: ServiceProtocol | None = None
    host: str | None = None
    port: int | None = Field(default=None, ge=1, le=65535)
    url: str | None = None
    health_url: str | None = None
    internal_url: str | None = None
    auth_type: ServiceAuthType | None = None
    auth_token: str | None = None
    auth_header_name: str | None = None
    json_metric_path: str | None = None
    expected_status: int | None = Field(default=None, ge=100, le=599)
    refresh_interval_seconds: int | None = Field(default=None, ge=5, le=3600)
    order: int | None = None
    enabled: bool | None = None
    verify_ssl: bool | None = None
    webhook_ttl_seconds: int | None = Field(default=None, ge=10, le=86400)
    alert_policy: AlertPolicyConfig | None = None


class ReorderServicesPayload(BaseModel):
    """Ordered list of custom service IDs (accepts service_ids, ids, or order)."""

    model_config = ConfigDict(extra="ignore")

    service_ids: list[str] = Field(default_factory=list)
    ids: list[str] | None = None
    order: list[str] | None = None

    @model_validator(mode="after")
    def _normalize_ids(self) -> "ReorderServicesPayload":
        if not self.service_ids:
            if self.ids:
                self.service_ids = list(self.ids)
            elif self.order:
                self.service_ids = list(self.order)
        return self


class CustomServiceTestPayload(BaseModel):
    """Optional override fields allowing live dry-run tests before saving."""

    model_config = ConfigDict(extra="ignore")

    id: str | None = None
    name: str | None = None
    protocol: ServiceProtocol | None = None
    host: str | None = None
    port: int | None = Field(default=None, ge=1, le=65535)
    url: str | None = None
    health_url: str | None = None
    internal_url: str | None = None
    auth_type: ServiceAuthType | None = None
    auth_token: str | None = None
    auth_header_name: str | None = None
    json_metric_path: str | None = None
    expected_status: int | None = Field(default=None, ge=100, le=599)
    verify_ssl: bool | None = None
    webhook_ttl_seconds: int | None = Field(default=None, ge=10, le=86400)


@router.get("")
async def list_custom_services(request: Request) -> dict[str, Any]:
    """List all custom services with live connector health, metrics, and persisted alert state."""
    cfg = get_config_manager().config
    state_store = _get_state_store(request)
    items = await check_custom_services(
        request.app.state.media_http,
        cfg.custom_services,
        state_store=state_store,
    )
    return {"services": items, "count": len(items)}


@router.post("", status_code=status.HTTP_201_CREATED)
async def create_custom_service(
    request: Request, payload: CustomServiceCreatePayload
) -> dict[str, Any]:
    """Create a new custom service and atomically persist it into config.yaml."""
    manager = get_config_manager()
    existing = list(manager.config.custom_services)
    existing_ids = {svc.id for svc in existing}

    requested_id = payload.id.strip()
    if requested_id:
        if requested_id in existing_ids:
            raise HTTPException(
                status_code=status.HTTP_409_CONFLICT,
                detail=f"Un service personnalisé avec l'id '{requested_id}' existe déjà.",
            )
        service_id = requested_id
    else:
        service_id = _slugify_id(payload.name, existing_ids)

    next_order = (
        payload.order
        if payload.order is not None
        else (max((svc.order for svc in existing), default=-1) + 1)
    )
    raw = payload.model_dump()
    raw["id"] = service_id
    raw["order"] = next_order
    new_service = CustomServiceConfig.model_validate(raw)

    updated_list = [*existing, new_service]
    manager.update_section(
        "custom_services",
        updated_list,
        preserve_templates=True,
        source="custom_services_create",
    )

    state_store = _get_state_store(request)
    state = (
        await state_store.get_service_state(service_id)
        if state_store is not None
        else None
    )
    return {"ok": True, "service": serialize_custom_service(new_service, state=state)}


@router.post("/reorder")
async def reorder_custom_services(payload: ReorderServicesPayload) -> dict[str, Any]:
    """Reorder custom services according to an ordered list of service IDs."""
    manager = get_config_manager()
    existing = list(manager.config.custom_services)
    by_id = {svc.id: svc for svc in existing}

    seen: set[str] = set()
    ordered_services: list[CustomServiceConfig] = []
    for svc_id in payload.service_ids:
        clean_id = svc_id.strip()
        if clean_id in by_id and clean_id not in seen:
            seen.add(clean_id)
            ordered_services.append(by_id[clean_id])

    for svc in existing:
        if svc.id not in seen:
            ordered_services.append(svc)

    reindexed = [
        svc.model_copy(update={"order": idx})
        for idx, svc in enumerate(ordered_services)
    ]
    manager.update_section(
        "custom_services",
        reindexed,
        preserve_templates=True,
        source="custom_services_reorder",
    )
    return {"ok": True, "order": [svc.id for svc in reindexed]}


@router.put("/{service_id}")
async def update_custom_service(
    request: Request, service_id: str, payload: CustomServiceUpdatePayload
) -> dict[str, Any]:
    """Update an existing custom service while preserving secret auth_token if blank/masked."""
    manager = get_config_manager()
    existing = list(manager.config.custom_services)

    idx = next((i for i, svc in enumerate(existing) if svc.id == service_id), None)
    if idx is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service personnalisé introuvable : {service_id}",
        )

    current = existing[idx]
    merged = current.model_dump()
    patch = payload.model_dump(exclude_unset=True)

    incoming_token = patch.pop("auth_token", None)
    merged.update({k: v for k, v in patch.items() if v is not None})
    if incoming_token is not None and not is_masked_or_empty(incoming_token):
        merged["auth_token"] = incoming_token

    updated_service = CustomServiceConfig.model_validate(merged)
    existing[idx] = updated_service
    manager.update_section(
        "custom_services",
        existing,
        preserve_templates=True,
        source="custom_services_update",
    )

    state_store = _get_state_store(request)
    state = (
        await state_store.get_service_state(service_id)
        if state_store is not None
        else None
    )
    return {"ok": True, "service": serialize_custom_service(updated_service, state=state)}


@router.delete("/{service_id}")
async def delete_custom_service(service_id: str) -> dict[str, Any]:
    """Delete a custom service and persist updated config.yaml."""
    manager = get_config_manager()
    existing = list(manager.config.custom_services)
    remaining = [svc for svc in existing if svc.id != service_id]
    if len(remaining) == len(existing):
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service personnalisé introuvable : {service_id}",
        )

    manager.update_section(
        "custom_services",
        remaining,
        preserve_templates=True,
        source="custom_services_delete",
    )
    return {"ok": True, "deleted_id": service_id}


@router.post("/{service_id}/test")
async def test_custom_service(
    request: Request,
    service_id: str,
    payload: CustomServiceTestPayload | None = Body(default=None),
) -> dict[str, Any]:
    """Run a live connector check on a saved custom service or unsaved dry-run payload."""
    manager = get_config_manager()
    saved = next(
        (svc for svc in manager.config.custom_services if svc.id == service_id),
        None,
    )

    if saved is None and payload is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service personnalisé introuvable : {service_id}",
        )

    base_dict: dict[str, Any] = (
        saved.model_dump()
        if saved is not None
        else {"id": service_id, "name": payload.name or service_id if payload else service_id}
    )
    if payload is not None:
        patch = payload.model_dump(exclude_unset=True)
        incoming_token = patch.pop("auth_token", None)
        base_dict.update({k: v for k, v in patch.items() if v is not None})
        if incoming_token is not None and not is_masked_or_empty(incoming_token):
            base_dict["auth_token"] = incoming_token

    target_cfg = CustomServiceConfig.model_validate(base_dict)
    state_store = _get_state_store(request)
    res = await run_connector(
        target_cfg,
        http_client=request.app.state.media_http,
        state_store=state_store,
    )
    return {
        "ok": res.ok,
        "service_id": target_cfg.id,
        "protocol": target_cfg.protocol,
        "status": res.status,
        "latency_ms": res.latency_ms,
        "http_status": res.http_status,
        "message": res.message,
        "metrics": res.metrics,
    }


def _extract_incoming_webhook_token(request: Request, svc: CustomServiceConfig) -> str:
    auth_header = request.headers.get("authorization", "")
    if auth_header.lower().startswith("bearer "):
        return auth_header[7:].strip()
    if svc.auth_header_name:
        custom_val = request.headers.get(svc.auth_header_name, "").strip()
        if custom_val:
            return custom_val
    for header_name in ("x-webhook-token", "x-api-key"):
        val = request.headers.get(header_name, "").strip()
        if val:
            return val
    return request.query_params.get("token", "").strip()


@router.post("/{service_id}/webhook")
async def ingest_service_webhook(
    request: Request,
    service_id: str,
    body: dict[str, Any] | None = Body(default=None),
) -> dict[str, Any]:
    """Ingest a push webhook heartbeat/status event for a webhook_ingest custom service."""
    manager = get_config_manager()
    svc = next(
        (item for item in manager.config.custom_services if item.id == service_id),
        None,
    )
    if svc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service personnalisé introuvable : {service_id}",
        )

    if svc.auth_type != "none" and is_secret_configured(svc.auth_token):
        presented = _extract_incoming_webhook_token(request, svc)
        if not presented or not hmac.compare_digest(presented, svc.auth_token):
            raise HTTPException(
                status_code=status.HTTP_401_UNAUTHORIZED,
                detail="Token webhook invalide ou manquant",
            )

    raw_body = body if isinstance(body, dict) else {}
    raw_status = str(raw_body.get("status") or "up").strip().lower()
    if raw_status not in ("up", "degraded", "down"):
        raw_status = "up"

    message = str(raw_body.get("message") or "").strip() or (
        "Webhook heartbeat reçu" if raw_status == "up" else f"Statut {raw_status} signalé via webhook"
    )
    ttl_seconds = int(raw_body.get("ttl_seconds") or svc.webhook_ttl_seconds or 300)
    ttl_seconds = max(10, min(ttl_seconds, 86400))

    metrics: dict[str, Any] = {}
    if isinstance(raw_body.get("metrics"), dict):
        metrics.update(raw_body["metrics"])
    reserved = {"status", "message", "metrics", "ttl_seconds"}
    for key, val in raw_body.items():
        if key not in reserved and isinstance(val, (str, int, float, bool)):
            metrics[key] = val

    state_store = _get_state_store(request)
    if state_store is None:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="StateStore non initialisé",
        )

    hb = await state_store.record_webhook_heartbeat(
        service_id,
        status=raw_status,
        message=message,
        metrics=metrics,
        ttl_seconds=ttl_seconds,
    )

    alert_engine = getattr(request.app.state, "alert_engine", None)
    eval_res: dict[str, Any] | None = None
    connector_res = ConnectorResult(
        ok=(raw_status == "up"),
        status=raw_status,
        latency_ms=0,
        http_status=200,
        message=message,
        metrics={**metrics, "ttl_seconds": ttl_seconds, "last_heartbeat_at": hb["received_at"]},
    )
    if alert_engine is not None:
        eval_res = await alert_engine.evaluate_service(
            svc, result=connector_res, app_config=manager.config
        )

    return {
        "ok": True,
        "service_id": service_id,
        "status": raw_status,
        "received_at": hb["received_at"],
        "ttl_seconds": hb["ttl_seconds"],
        "metrics": hb["metrics"],
        "incident_created": eval_res.get("incident_created") if eval_res else None,
        "incidents_resolved": eval_res.get("incidents_resolved", []) if eval_res else [],
    }
