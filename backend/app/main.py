"""FastAPI entrypoint serving APIs and static React frontend."""

from contextlib import asynccontextmanager
from pathlib import Path

import httpx
from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from app.config import get_settings
from app.middleware.tailscale_auth import TailscaleSSOMiddleware
from app.routers import auth, operations, proxmox, services, users, widgets


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Manage shared async HTTP connection pools across requests."""
    settings = get_settings()
    app.state.pve_http = httpx.AsyncClient(
        verify=settings.pve_verify_ssl, timeout=httpx.Timeout(5.0, connect=3.0)
    )
    app.state.media_http = httpx.AsyncClient(
        verify=False, timeout=httpx.Timeout(3.5, connect=2.5)
    )
    try:
        yield
    finally:
        await app.state.pve_http.aclose()
        await app.state.media_http.aclose()


app = FastAPI(
    title="PVE Command Center",
    description="Panel d'administration privé sécurisé via Tailscale Serve",
    version="1.0.0",
    docs_url=None,
    redoc_url=None,
    lifespan=lifespan,
)

app.add_middleware(TailscaleSSOMiddleware)

app.include_router(auth.router)
app.include_router(proxmox.router)
app.include_router(services.router)
app.include_router(widgets.router)
app.include_router(users.router)
app.include_router(operations.router)


@app.get("/api/health")
async def health() -> dict[str, str]:
    """Simple authenticated liveness endpoint."""
    return {"status": "ok"}


_static_dir = get_settings().resolve_static_dir()
if _static_dir:
    assets_dir = _static_dir / "assets"
    if assets_dir.is_dir():
        app.mount("/assets", StaticFiles(directory=str(assets_dir)), name="assets")

    @app.api_route("/{full_path:path}", methods=["GET", "HEAD"], include_in_schema=False)
    async def serve_spa(full_path: str):
        """Serve static assets or fallback to React index.html for SPA routes."""
        if full_path.startswith("api"):
            return JSONResponse(status_code=404, content={"detail": "Not Found"})
        candidate = (_static_dir / full_path).resolve()
        if (
            full_path
            and candidate.is_file()
            and str(candidate).startswith(str(_static_dir.resolve()))
        ):
            return FileResponse(candidate)
        return FileResponse(_static_dir / "index.html")
else:

    @app.get("/", include_in_schema=False)
    async def missing_frontend() -> JSONResponse:
        return JSONResponse(
            status_code=503,
            content={"detail": "Frontend non compilé (frontend/dist introuvable)."},
        )
