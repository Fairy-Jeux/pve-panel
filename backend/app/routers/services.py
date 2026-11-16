"""Service catalog and live healthcheck endpoints."""

from fastapi import APIRouter, Request

from app.config_manager import get_config_manager
from app.services.media_clients import check_services_overview

router = APIRouter(prefix="/api", tags=["services"])


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
