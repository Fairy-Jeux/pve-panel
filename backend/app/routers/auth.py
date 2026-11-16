"""Authentication info endpoint exposing the verified Tailscale user."""

from fastapi import APIRouter, Request

router = APIRouter(prefix="/api", tags=["auth"])


@router.get("/me")
async def get_current_user(request: Request) -> dict:
    """Return the authenticated Tailscale identity from middleware state."""
    return getattr(request.state, "user", {"login": "unknown", "name": "Unknown"})
