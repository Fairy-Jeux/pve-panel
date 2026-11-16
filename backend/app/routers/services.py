"""Service catalog and live healthcheck endpoints."""

from fastapi import APIRouter, Request

from app.config import load_services_config
from app.services.media_clients import check_categories_health

router = APIRouter(prefix="/api", tags=["services"])


@router.get("/services")
async def list_services_with_health(request: Request) -> dict:
    """Load services.yaml dynamically and run concurrent healthchecks."""
    categories = load_services_config()
    checked = await check_categories_health(request.app.state.media_http, categories)
    return {"categories": checked}
