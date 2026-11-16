"""Tailscale Serve SSO & Anti-Spoofing authentication middleware."""

from starlette.middleware.base import BaseHTTPMiddleware
from starlette.requests import Request
from starlette.responses import HTMLResponse, JSONResponse, Response

from app.config import get_settings

LOCAL_LOOPBACK_IPS = {"127.0.0.1", "::1", "localhost"}


def _deny_response(request: Request, reason: str) -> Response:
    """Return JSON 403 for API calls or minimal HTML 403 for browser requests."""
    if request.url.path.startswith("/api"):
        return JSONResponse(status_code=403, content={"detail": reason})
    html = (
        "<!doctype html><html lang='fr'><head><meta charset='utf-8'>"
        "<title>403 Forbidden</title></head><body style='background:#020617;"
        "color:#f87171;font-family:system-ui,sans-serif;display:grid;"
        "place-items:center;height:100vh;margin:0'>"
        f"<div style='text-align:center'><h1>403 — Accès refusé</h1>"
        f"<p style='color:#94a3b8'>{reason}</p></div></body></html>"
    )
    return HTMLResponse(status_code=403, content=html)


class TailscaleSSOMiddleware(BaseHTTPMiddleware):
    """Enforce loopback origin + Tailscale-User-Login whitelist (with dev bypass)."""

    async def dispatch(self, request: Request, call_next) -> Response:
        settings = get_settings()
        client_host = request.client.host if request.client else ""

        # Verrou 1 (Anti-Spoofing) : même en dev bypass, n'accepter que loopback locale
        if client_host not in LOCAL_LOOPBACK_IPS:
            return _deny_response(
                request,
                "Origine réseau non autorisée : connexion directe hors tailscale serve bloquée.",
            )

        if settings.dev_auth_bypass:
            primary_user = (
                next(iter(settings.allowed_users_set), "dev@localhost")
                if settings.allowed_users_set
                else "dev@localhost"
            )
            request.state.user = {
                "login": primary_user,
                "name": "Admin (Mode Dev Local)",
                "profile_pic": "",
                "auth_mode": "dev_bypass",
            }
            return await call_next(request)

        # Verrou 2 (SSO Tailscale Serve) : vérifier l'identité cryptographiquement injectée
        ts_login = (request.headers.get("Tailscale-User-Login") or "").strip().lower()
        if not ts_login:
            return _deny_response(
                request,
                "Authentification Tailscale Serve manquante.",
            )

        if ts_login not in settings.allowed_users_set:
            return _deny_response(
                request,
                f"Utilisateur '{ts_login}' non autorisé à accéder à ce panneau.",
            )

        request.state.user = {
            "login": ts_login,
            "name": (request.headers.get("Tailscale-User-Name") or ts_login).strip(),
            "profile_pic": (
                request.headers.get("Tailscale-User-Profile-Pic") or ""
            ).strip(),
            "auth_mode": "tailscale_serve",
        }
        return await call_next(request)
