"""Service catalog, live healthchecks, and customization endpoints for categorized apps."""

from __future__ import annotations

from typing import Any, Literal

from fastapi import APIRouter, Body, HTTPException, Request, status
from pydantic import BaseModel, ConfigDict, Field

from app.config import load_services_config, persist_categories_config
from app.config_manager import get_config_manager
from app.config_schema import CategoryServiceConfig
from app.services.media_clients import check_services_overview, check_single_service
from app.services.realtime_bus import get_realtime_bus

router = APIRouter(prefix="/api", tags=["services"])


class CategoryServiceUpdatePayload(BaseModel):
    """Update payload allowing any categorized app card to be customized in-place."""

    model_config = ConfigDict(extra="ignore")

    name: str | None = Field(default=None, min_length=1)
    description: str | None = None
    url: str | None = None
    ping_url: str | None = None
    icon: str | None = None
    widget: str | None = None
    category: str | None = None


class CategoryServiceMovePayload(BaseModel):
    """Reorder payload moving a categorized app earlier or later inside its category."""

    model_config = ConfigDict(extra="ignore")

    direction: Literal["up", "down"]


class CategoryServiceTestPayload(BaseModel):
    """Optional unsaved URL overrides for live healthcheck dry-run inside edit modal."""

    model_config = ConfigDict(extra="ignore")

    url: str | None = None
    ping_url: str | None = None


async def _emit_categories_reload(source: str) -> None:
    manager = get_config_manager()
    if not manager.config_exists:
        await get_realtime_bus().publish(
            "config_reloaded",
            {
                "hash": manager.content_hash,
                "source": source,
                "server_id": manager.config.server.id,
                "is_synthesized": manager.is_synthesized,
            },
        )


def _find_category_service(
    categories: list[dict[str, Any]], service_id: str
) -> tuple[int, int] | None:
    for cat_idx, cat in enumerate(categories):
        for svc_idx, svc in enumerate(cat.get("services") or []):
            if str(svc.get("id") or "") == service_id:
                return cat_idx, svc_idx
    return None


@router.get("/services")
async def list_services_with_health(request: Request) -> dict:
    """Load config categories + custom_services dynamically and run concurrent healthchecks."""
    cfg = get_config_manager().config
    state_store = getattr(request.app.state, "state_store", None)
    return await check_services_overview(
        request.app.state.media_http,
        cfg,
        state_store=state_store,
    )


@router.put("/services/items/{service_id}")
async def update_category_service(
    request: Request, service_id: str, payload: CategoryServiceUpdatePayload
) -> dict[str, Any]:
    """Customize name, icon, URLs, widget, or category for any service in categories."""
    categories = load_services_config()
    loc = _find_category_service(categories, service_id)
    if loc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service introuvable dans les catégories : {service_id}",
        )

    cat_idx, svc_idx = loc
    current_svc = dict(categories[cat_idx]["services"][svc_idx])
    current_cat_name = str(categories[cat_idx].get("name") or "Services")

    patch = payload.model_dump(exclude_unset=True)
    target_cat_name = str(patch.pop("category", None) or current_cat_name).strip() or "Services"

    for key, val in patch.items():
        if val is None:
            continue
        cleaned = val.strip() if isinstance(val, str) else val
        if key == "widget" and not cleaned:
            current_svc.pop("widget", None)
        else:
            current_svc[key] = cleaned

    validated_item = CategoryServiceConfig.model_validate(current_svc).model_dump(exclude_none=True)

    if target_cat_name.lower() == current_cat_name.lower():
        categories[cat_idx]["services"][svc_idx] = validated_item
    else:
        categories[cat_idx]["services"].pop(svc_idx)
        if not categories[cat_idx]["services"]:
            categories.pop(cat_idx)
        dest_cat = next(
            (c for c in categories if str(c.get("name") or "").strip().lower() == target_cat_name.lower()),
            None,
        )
        if dest_cat is None:
            categories.append({"name": target_cat_name, "services": [validated_item]})
        else:
            dest_cat["services"].append(validated_item)

    persist_categories_config(categories, source="category_service_update")
    await _emit_categories_reload("category_service_update")
    checked = await check_single_service(request.app.state.media_http, validated_item)
    return {"ok": True, "category": target_cat_name, "service": checked}


@router.post("/services/items/{service_id}/move")
async def move_category_service(
    service_id: str, payload: CategoryServiceMovePayload
) -> dict[str, Any]:
    """Move a service earlier or later within its category."""
    categories = load_services_config()
    loc = _find_category_service(categories, service_id)
    if loc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service introuvable : {service_id}",
        )

    cat_idx, svc_idx = loc
    svcs = categories[cat_idx]["services"]
    target_idx = svc_idx - 1 if payload.direction == "up" else svc_idx + 1
    if 0 <= target_idx < len(svcs):
        svcs[svc_idx], svcs[target_idx] = svcs[target_idx], svcs[svc_idx]
        persist_categories_config(categories, source="category_service_move")
        await _emit_categories_reload("category_service_move")
    return {"ok": True, "service_id": service_id}


@router.post("/services/items/{service_id}/test")
async def test_category_service(
    request: Request,
    service_id: str,
    payload: CategoryServiceTestPayload | None = Body(default=None),
) -> dict[str, Any]:
    """Run an immediate HTTP healthcheck against a saved or unsaved category service URL."""
    categories = load_services_config()
    loc = _find_category_service(categories, service_id)
    if loc is None and payload is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service introuvable : {service_id}",
        )
    target: dict[str, Any] = (
        dict(categories[loc[0]]["services"][loc[1]]) if loc is not None else {"id": service_id}
    )
    if payload is not None:
        if payload.url is not None:
            target["url"] = payload.url.strip()
        if payload.ping_url is not None:
            target["ping_url"] = payload.ping_url.strip()

    checked = await check_single_service(request.app.state.media_http, target)
    ok = bool(checked.get("online"))
    code = checked.get("status_code")
    latency = checked.get("latency_ms")
    msg = (
        f"Joignable (HTTP {code})" if ok and code is not None else "Service joignable" if ok else (f"HTTP {code}" if code is not None else "Hôte injoignable ou timeout")
    )
    return {
        "ok": ok,
        "service_id": service_id,
        "online": ok,
        "status_code": code,
        "latency_ms": latency,
        "message": msg,
    }


@router.delete("/services/items/{service_id}")
async def delete_category_service(service_id: str) -> dict[str, Any]:
    """Delete a service entry from its category."""
    categories = load_services_config()
    loc = _find_category_service(categories, service_id)
    if loc is None:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=f"Service introuvable : {service_id}",
        )

    cat_idx, svc_idx = loc
    categories[cat_idx]["services"].pop(svc_idx)
    if not categories[cat_idx]["services"]:
        categories.pop(cat_idx)

    persist_categories_config(categories, source="category_service_delete")
    await _emit_categories_reload("category_service_delete")
    return {"ok": True, "deleted_id": service_id}
