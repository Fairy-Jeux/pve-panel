"""Unified user provisioning and management between Jellyfin and Jellyseerr."""

import asyncio
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from pydantic import BaseModel, Field

from app.config import get_settings

router = APIRouter(prefix="/api/users", tags=["users"])

SEERR_FRIEND_AUTO_APPROVE_PERMS = 8388768
SEERR_FRIEND_MANUAL_PERMS = 32
SEERR_PERM_ADMIN = 2
SEERR_PERM_AUTO_APPROVE = 128

_POLICY_FIELD_MAP = (
    ("is_disabled", "IsDisabled"),
    ("is_admin", "IsAdministrator"),
    ("enable_all_folders", "EnableAllFolders"),
    ("enabled_folders", "EnabledFolders"),
    ("enable_downloading", "EnableContentDownloading"),
    ("max_active_sessions", "MaxActiveSessions"),
)


class CreateUserPayload(BaseModel):
    """Request payload for creating a Jellyfin user and syncing to Jellyseerr."""

    username: str = Field(..., min_length=2, max_length=64)
    password: str = Field(..., min_length=4, max_length=128)
    sync_jellyseerr: bool = True
    auto_approve: bool = True
    enable_all_folders: bool = True
    enabled_folders: list[str] = Field(default_factory=list)
    enable_downloading: bool = True
    max_active_sessions: int = Field(default=0, ge=0, le=20)


class UpdateUserPayload(BaseModel):
    """Request payload for updating Jellyfin policies and Jellyseerr permissions."""

    is_disabled: bool | None = None
    is_admin: bool | None = None
    enable_all_folders: bool | None = None
    enabled_folders: list[str] | None = None
    enable_downloading: bool | None = None
    max_active_sessions: int | None = Field(default=None, ge=0, le=20)
    auto_approve: bool | None = None


class ResetPasswordPayload(BaseModel):
    """Request payload for resetting and setting a Jellyfin user's password."""

    new_password: str = Field(..., min_length=4, max_length=128)


class SyncUsersPayload(BaseModel):
    """Request payload for importing existing Jellyfin users into Jellyseerr."""

    jellyfin_user_ids: list[str] | None = None
    auto_approve: bool = True


def _norm_id(raw_id: str | None) -> str:
    return (raw_id or "").replace("-", "").strip().lower()


def _jf_headers(api_key: str) -> dict[str, str]:
    return {
        "Authorization": f'MediaBrowser Token="{api_key}"',
        "Content-Type": "application/json",
    }


def _seerr_headers(api_key: str) -> dict[str, str]:
    return {"X-Api-Key": api_key, "Content-Type": "application/json"}


def _jf_config() -> tuple[str, dict[str, str]]:
    """Return Jellyfin base URL and auth headers, or raise 503 if unconfigured."""
    settings = get_settings()
    if not settings.jellyfin_url or not settings.jellyfin_api_key:
        raise HTTPException(status_code=503, detail="Jellyfin non configuré dans .env")
    return settings.jellyfin_url.rstrip("/"), _jf_headers(settings.jellyfin_api_key)


def _seerr_config(*, required: bool = True) -> tuple[str, dict[str, str]] | None:
    """Return Jellyseerr base URL and auth headers, raising 503 when required."""
    settings = get_settings()
    if not settings.jellyseerr_url or not settings.jellyseerr_api_key:
        if required:
            raise HTTPException(
                status_code=503, detail="Jellyseerr non configuré dans .env"
            )
        return None
    return settings.jellyseerr_url.rstrip("/"), _seerr_headers(
        settings.jellyseerr_api_key
    )


def _is_owner(jf_user: dict[str, Any]) -> bool:
    """Return True if the Jellyfin user is the protected owner account."""
    owner = get_settings().protected_owner_username.strip().lower()
    return bool(owner) and str(jf_user.get("Name") or "").strip().lower() == owner


async def _send_request(
    client: httpx.AsyncClient,
    method: str,
    url: str,
    *,
    error_detail: str,
    not_found_detail: str | None = None,
    bad_request_status: bool = False,
    **kwargs: Any,
) -> httpx.Response:
    """Execute an HTTP request and map transport or status errors to HTTPException."""
    try:
        resp = await client.request(method, url, **kwargs)
    except httpx.HTTPError as exc:
        raise HTTPException(status_code=502, detail=f"{error_detail} : {exc}") from exc

    if resp.status_code == 404 and not_found_detail:
        raise HTTPException(status_code=404, detail=not_found_detail)
    if resp.status_code >= 400:
        status = 400 if (bad_request_status and resp.status_code == 400) else 502
        raise HTTPException(
            status_code=status,
            detail=f"{error_detail} ({resp.status_code}) : {resp.text[:200]}",
        )
    return resp


async def _fetch_jf_user(
    client: httpx.AsyncClient,
    jf_base: str,
    headers: dict[str, str],
    jellyfin_id: str,
) -> dict[str, Any]:
    """Fetch a single Jellyfin user object by ID."""
    resp = await _send_request(
        client,
        "GET",
        f"{jf_base}/Users/{jellyfin_id}",
        headers=headers,
        error_detail="Impossible de récupérer l'utilisateur Jellyfin",
        not_found_detail="Utilisateur Jellyfin introuvable.",
        timeout=4.0,
    )
    return resp.json()


async def _update_jf_policy(
    client: httpx.AsyncClient,
    jf_base: str,
    headers: dict[str, str],
    jellyfin_id: str,
    policy_updates: dict[str, Any],
    existing_user: dict[str, Any] | None = None,
) -> None:
    """Fetch full Jellyfin policy if needed, merge updates, and persist via POST."""
    user = existing_user or await _fetch_jf_user(client, jf_base, headers, jellyfin_id)
    policy = dict(user.get("Policy") or {})
    policy.update(policy_updates)
    await _send_request(
        client,
        "POST",
        f"{jf_base}/Users/{jellyfin_id}/Policy",
        headers=headers,
        json=policy,
        error_detail="Erreur mise à jour des permissions Jellyfin",
        timeout=5.0,
    )


async def _fetch_seerr_users(
    client: httpx.AsyncClient,
    seerr_base: str,
    seerr_headers: dict[str, str],
    *,
    required_ok: bool = False,
) -> list[dict[str, Any]]:
    """Fetch Jellyseerr users, optionally tolerating errors when optional."""
    if required_ok:
        resp = await _send_request(
            client,
            "GET",
            f"{seerr_base}/api/v1/user",
            params={"take": 100},
            headers=seerr_headers,
            error_detail="Impossible de récupérer les utilisateurs Jellyseerr",
            timeout=4.0,
        )
        return resp.json().get("results", [])

    try:
        resp = await client.get(
            f"{seerr_base}/api/v1/user",
            params={"take": 100},
            headers=seerr_headers,
            timeout=4.0,
        )
        if resp.status_code == 200:
            return resp.json().get("results", [])
    except httpx.HTTPError:
        pass
    return []


async def _find_mutable_seerr_id(
    client: httpx.AsyncClient,
    jellyfin_id: str,
    *,
    required_ok: bool,
) -> tuple[str, dict[str, str], int] | None:
    """Return (seerr_base, headers, seerr_id) for matching non-owner Jellyseerr user."""
    seerr_cfg = _seerr_config(required=False)
    if not seerr_cfg:
        return None
    seerr_base, seerr_headers = seerr_cfg
    seerr_users = await _fetch_seerr_users(
        client, seerr_base, seerr_headers, required_ok=required_ok
    )
    target = _norm_id(jellyfin_id)
    for user in seerr_users:
        if _norm_id(user.get("jellyfinUserId")) == target:
            if user.get("id") is None:
                return None
            seerr_id = int(user["id"])
            return None if seerr_id == 1 else (seerr_base, seerr_headers, seerr_id)
    return None


async def _set_seerr_permissions(
    client: httpx.AsyncClient,
    seerr_base: str,
    seerr_headers: dict[str, str],
    user_ids: list[int],
    permissions: int,
    error_detail: str,
) -> None:
    """Apply a permission bitmask to the given Jellyseerr user IDs."""
    await _send_request(
        client,
        "PUT",
        f"{seerr_base}/api/v1/user",
        headers=seerr_headers,
        json={"ids": user_ids, "permissions": permissions},
        error_detail=error_detail,
        timeout=5.0,
    )


async def _fetch_overview_sources(
    client: httpx.AsyncClient, *, include_libraries: bool = False
) -> tuple[list[dict[str, Any]], list[dict[str, Any]], list[dict[str, str]]]:
    """Fetch Jellyfin users and optionally libraries & Jellyseerr users concurrently."""
    jf_base, jf_headers = _jf_config()
    seerr_cfg = _seerr_config(required=False)

    tasks: list[Any] = [
        client.get(f"{jf_base}/Users", headers=jf_headers, timeout=4.0)
    ]
    if include_libraries:
        tasks.append(
            client.get(
                f"{jf_base}/Library/VirtualFolders", headers=jf_headers, timeout=4.0
            )
        )
    if seerr_cfg:
        seerr_base, seerr_headers = seerr_cfg
        tasks.append(
            client.get(
                f"{seerr_base}/api/v1/user",
                params={"take": 100},
                headers=seerr_headers,
                timeout=4.0,
            )
        )

    results = await asyncio.gather(*tasks, return_exceptions=True)
    idx = 0
    jf_resp = results[idx]
    idx += 1

    if isinstance(jf_resp, Exception) or jf_resp.status_code >= 400:
        raise HTTPException(
            status_code=502, detail="Impossible de récupérer les utilisateurs Jellyfin."
        )

    libraries: list[dict[str, str]] = []
    if include_libraries:
        folders_resp = results[idx]
        idx += 1
        if (
            not isinstance(folders_resp, Exception)
            and folders_resp.status_code == 200
        ):
            folders = folders_resp.json()
            if isinstance(folders, list):
                libraries = [
                    {"id": str(f.get("ItemId", "")), "name": str(f.get("Name", ""))}
                    for f in folders
                    if isinstance(f, dict) and f.get("ItemId") and f.get("Name")
                ]

    seerr_users: list[dict[str, Any]] = []
    if seerr_cfg:
        seerr_resp = results[idx]
        if not isinstance(seerr_resp, Exception) and seerr_resp.status_code == 200:
            seerr_users = seerr_resp.json().get("results", [])

    return jf_resp.json(), seerr_users, libraries


async def _import_into_jellyseerr(
    client: httpx.AsyncClient,
    jellyfin_ids: list[str],
    auto_approve: bool,
) -> list[dict[str, Any]]:
    """Import given Jellyfin user IDs into Jellyseerr and optionally grant auto-approve."""
    if not jellyfin_ids:
        return []
    seerr_base, headers = _seerr_config(required=True)  # type: ignore[misc]

    resp = await _send_request(
        client,
        "POST",
        f"{seerr_base}/api/v1/user/import-from-jellyfin",
        headers=headers,
        json={"jellyfinUserIds": jellyfin_ids},
        error_detail="Échec import Jellyseerr",
        timeout=6.0,
    )

    created = resp.json() if resp.text else []
    created_ids = [int(u["id"]) for u in created if "id" in u]

    if auto_approve and created_ids:
        await _set_seerr_permissions(
            client,
            seerr_base,
            headers,
            created_ids,
            SEERR_FRIEND_AUTO_APPROVE_PERMS,
            "Importé dans Jellyseerr, mais échec permissions",
        )

    return created


@router.get("")
async def list_unified_users(request: Request) -> dict[str, Any]:
    """Return Jellyfin users, libraries, and Jellyseerr sync & permission state."""
    client: httpx.AsyncClient = request.app.state.media_http
    jf_users, seerr_users, libraries = await _fetch_overview_sources(
        client, include_libraries=True
    )

    seerr_by_jf_id = {
        _norm_id(u.get("jellyfinUserId")): u
        for u in seerr_users
        if u.get("jellyfinUserId")
    }

    unified: list[dict[str, Any]] = []
    for jf in sorted(jf_users, key=lambda x: str(x.get("Name", "")).lower()):
        jf_id = str(jf.get("Id", ""))
        policy = jf.get("Policy") or {}
        is_admin = bool(policy.get("IsAdministrator", False))
        is_disabled = bool(policy.get("IsDisabled", False))
        seerr = seerr_by_jf_id.get(_norm_id(jf_id))

        perms = int(seerr.get("permissions") or 0) if seerr else 0
        auto_approve = (
            is_admin
            or (perms & SEERR_PERM_ADMIN) != 0
            or (perms & SEERR_PERM_AUTO_APPROVE) != 0
        )

        unified.append(
            {
                "jellyfin_id": jf_id,
                "name": jf.get("Name", "Utilisateur"),
                "is_admin": is_admin,
                "is_protected": _is_owner(jf),
                "is_disabled": is_disabled,
                "enable_all_folders": bool(policy.get("EnableAllFolders", True)),
                "enabled_folders": list(policy.get("EnabledFolders") or []),
                "enable_downloading": bool(policy.get("EnableContentDownloading", True)),
                "max_active_sessions": int(policy.get("MaxActiveSessions") or 0),
                "last_activity": jf.get("LastActivityDate"),
                "in_jellyseerr": seerr is not None,
                "jellyseerr_id": seerr.get("id") if seerr else None,
                "request_count": int(seerr.get("requestCount") or 0) if seerr else 0,
                "auto_approve": auto_approve,
            }
        )

    synced_count = sum(1 for u in unified if u["in_jellyseerr"])
    disabled_count = sum(1 for u in unified if u["is_disabled"])
    return {
        "counts": {
            "total_jellyfin": len(unified),
            "synced_jellyseerr": synced_count,
            "unsynced_count": len(unified) - synced_count,
            "disabled_count": disabled_count,
        },
        "libraries": libraries,
        "users": unified,
    }


@router.post("")
async def create_user(request: Request, payload: CreateUserPayload) -> dict[str, Any]:
    """Create a user on Jellyfin, apply policy options, and replicate to Jellyseerr."""
    jf_base, jf_headers = _jf_config()
    client: httpx.AsyncClient = request.app.state.media_http
    username = payload.username.strip()

    if not username:
        raise HTTPException(status_code=400, detail="Nom d'utilisateur invalide.")

    jf_resp = await _send_request(
        client,
        "POST",
        f"{jf_base}/Users/New",
        headers=jf_headers,
        json={"Name": username, "Password": payload.password},
        error_detail="Erreur création Jellyfin",
        bad_request_status=True,
        timeout=5.0,
    )

    jf_user = jf_resp.json()
    jf_id = str(jf_user.get("Id", ""))

    if jf_id and (
        not payload.enable_all_folders
        or not payload.enable_downloading
        or payload.max_active_sessions > 0
    ):
        await _update_jf_policy(
            client,
            jf_base,
            jf_headers,
            jf_id,
            {
                "EnableAllFolders": payload.enable_all_folders,
                "EnabledFolders": list(payload.enabled_folders),
                "EnableContentDownloading": payload.enable_downloading,
                "MaxActiveSessions": payload.max_active_sessions,
            },
        )

    seerr_created: list[dict[str, Any]] = []
    if payload.sync_jellyseerr and jf_id:
        seerr_created = await _import_into_jellyseerr(
            client, [jf_id], auto_approve=payload.auto_approve
        )

    return {
        "ok": True,
        "username": jf_user.get("Name", username),
        "jellyfin_id": jf_id,
        "synced_jellyseerr": bool(seerr_created),
        "jellyseerr_id": seerr_created[0].get("id") if seerr_created else None,
        "auto_approve": payload.auto_approve,
    }


@router.post("/sync")
async def sync_missing_users(
    request: Request, payload: SyncUsersPayload
) -> dict[str, Any]:
    """Import missing Jellyfin users (or given IDs) into Jellyseerr."""
    client: httpx.AsyncClient = request.app.state.media_http
    target_ids = payload.jellyfin_user_ids

    if not target_ids:
        jf_users, seerr_users, _ = await _fetch_overview_sources(client)
        existing_seerr_ids = {
            _norm_id(u.get("jellyfinUserId"))
            for u in seerr_users
            if u.get("jellyfinUserId")
        }
        target_ids = [
            str(u["Id"])
            for u in jf_users
            if _norm_id(str(u.get("Id", ""))) not in existing_seerr_ids
        ]

    if not target_ids:
        return {"ok": True, "imported_count": 0, "users": []}

    created = await _import_into_jellyseerr(
        client, target_ids, auto_approve=payload.auto_approve
    )
    return {"ok": True, "imported_count": len(created), "users": created}


@router.patch("/{jellyfin_id}")
async def update_user(
    request: Request, jellyfin_id: str, payload: UpdateUserPayload
) -> dict[str, Any]:
    """Update a user's Jellyfin policy flags and Jellyseerr auto-approve permission."""
    jf_base, jf_headers = _jf_config()
    client: httpx.AsyncClient = request.app.state.media_http

    jf_user = await _fetch_jf_user(client, jf_base, jf_headers, jellyfin_id)
    if _is_owner(jf_user) and (
        payload.is_disabled is True or payload.is_admin is False
    ):
        raise HTTPException(
            status_code=400,
            detail="Impossible de désactiver ou rétrograder le compte propriétaire protégé.",
        )

    policy_updates = {
        jf_key: getattr(payload, field)
        for field, jf_key in _POLICY_FIELD_MAP
        if getattr(payload, field) is not None
    }
    if policy_updates:
        await _update_jf_policy(
            client,
            jf_base,
            jf_headers,
            jellyfin_id,
            policy_updates,
            existing_user=jf_user,
        )

    if payload.auto_approve is not None:
        match = await _find_mutable_seerr_id(client, jellyfin_id, required_ok=True)
        if match:
            seerr_base, seerr_headers, seerr_id = match
            perms = (
                SEERR_FRIEND_AUTO_APPROVE_PERMS
                if payload.auto_approve
                else SEERR_FRIEND_MANUAL_PERMS
            )
            await _set_seerr_permissions(
                client,
                seerr_base,
                seerr_headers,
                [seerr_id],
                perms,
                "Erreur mise à jour permissions Jellyseerr",
            )

    return {"ok": True, "jellyfin_id": jellyfin_id}


@router.post("/{jellyfin_id}/password")
async def reset_user_password(
    request: Request, jellyfin_id: str, payload: ResetPasswordPayload
) -> dict[str, Any]:
    """Reset and assign a new password for a Jellyfin user."""
    jf_base, jf_headers = _jf_config()
    client: httpx.AsyncClient = request.app.state.media_http

    await _send_request(
        client,
        "POST",
        f"{jf_base}/Users/{jellyfin_id}/Password",
        headers=jf_headers,
        json={"ResetPassword": True},
        error_detail="Échec réinitialisation mot de passe Jellyfin",
        timeout=5.0,
    )
    await _send_request(
        client,
        "POST",
        f"{jf_base}/Users/{jellyfin_id}/Password",
        headers=jf_headers,
        json={"NewPw": payload.new_password},
        error_detail="Échec définition mot de passe Jellyfin",
        timeout=5.0,
    )
    return {"ok": True}


@router.delete("/{jellyfin_id}")
async def delete_user(request: Request, jellyfin_id: str) -> dict[str, Any]:
    """Delete a user from Jellyseerr (if present) and Jellyfin."""
    jf_base, jf_headers = _jf_config()
    client: httpx.AsyncClient = request.app.state.media_http

    jf_user = await _fetch_jf_user(client, jf_base, jf_headers, jellyfin_id)
    if _is_owner(jf_user):
        raise HTTPException(
            status_code=400,
            detail="Suppression du compte propriétaire protégé interdite.",
        )

    deleted_seerr = False
    match = await _find_mutable_seerr_id(client, jellyfin_id, required_ok=False)
    if match:
        seerr_base, seerr_headers, seerr_id = match
        await _send_request(
            client,
            "DELETE",
            f"{seerr_base}/api/v1/user/{seerr_id}",
            headers=seerr_headers,
            error_detail="Erreur suppression Jellyseerr",
            timeout=5.0,
        )
        deleted_seerr = True

    await _send_request(
        client,
        "DELETE",
        f"{jf_base}/Users/{jellyfin_id}",
        headers=jf_headers,
        error_detail="Erreur suppression Jellyfin",
        timeout=5.0,
    )
    return {
        "ok": True,
        "deleted_jellyfin": True,
        "deleted_jellyseerr": deleted_seerr,
    }
