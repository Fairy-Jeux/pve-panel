"""Configuration loader for environment variables and dynamic services.yaml."""

from functools import lru_cache
from pathlib import Path
from typing import Any

import yaml
from pydantic_settings import BaseSettings, SettingsConfigDict


def _find_env_file() -> str | None:
    """Locate .env file in current dir, parent dir, or repo root."""
    candidates = [
        Path.cwd() / ".env",
        Path.cwd().parent / ".env",
        Path(__file__).resolve().parents[2] / ".env",
    ]
    for path in candidates:
        if path.is_file():
            return str(path)
    return None


class Settings(BaseSettings):
    """Typed application settings loaded from environment / .env."""

    model_config = SettingsConfigDict(
        env_file=_find_env_file(),
        env_file_encoding="utf-8",
        extra="ignore",
    )

    dev_auth_bypass: bool = False
    allowed_tailscale_users: str = ""
    protected_owner_username: str = "admin"

    services_config_path: str = "../services.yaml"
    static_dir: str = ""

    pve_host: str = "https://192.168.1.110:8006"
    pve_node: str = "pve"
    pve_token_id: str = ""
    pve_token_secret: str = ""
    pve_verify_ssl: bool = False
    panel_self_vmid: int = 116

    jellyfin_url: str = ""
    jellyfin_api_key: str = ""

    jellyseerr_url: str = ""
    jellyseerr_api_key: str = ""

    plex_url: str = ""
    plex_token: str = ""

    radarr_url: str = ""
    radarr_api_key: str = ""

    sonarr_url: str = ""
    sonarr_api_key: str = ""

    prowlarr_url: str = ""
    prowlarr_api_key: str = ""

    qbit_url: str = ""
    qbit_username: str = ""
    qbit_password: str = ""

    @property
    def allowed_users_set(self) -> set[str]:
        """Normalized lowercase set of allowed Tailscale login emails."""
        return {
            u.strip().lower()
            for u in self.allowed_tailscale_users.split(",")
            if u.strip()
        }

    def resolve_services_yaml(self) -> Path:
        """Resolve services.yaml dynamically across dev and container layouts."""
        configured = Path(self.services_config_path)
        if configured.is_file():
            return configured
        project_root = Path(__file__).resolve().parents[2] / "services.yaml"
        if project_root.is_file():
            return project_root
        return Path("/app/services.yaml")

    def resolve_static_dir(self) -> Path | None:
        """Locate compiled React frontend static directory."""
        candidates = []
        if self.static_dir:
            candidates.append(Path(self.static_dir))
        candidates.extend(
            [
                Path("/app/static"),
                Path(__file__).resolve().parents[2] / "frontend" / "dist",
            ]
        )
        for path in candidates:
            if path.is_dir() and (path / "index.html").is_file():
                return path
        return None


@lru_cache(maxsize=1)
def get_settings() -> Settings:
    """Return cached Settings instance."""
    return Settings()


def _read_services_yaml_raw() -> dict[str, Any]:
    """Read raw services.yaml mapping dynamically without caching across edits."""
    yaml_path = get_settings().resolve_services_yaml()
    if not yaml_path.is_file():
        return {}
    with yaml_path.open("r", encoding="utf-8") as fh:
        data = yaml.safe_load(fh)
    return data if isinstance(data, dict) else {}


def load_services_config() -> list[dict[str, Any]]:
    """Read service categories from services.yaml."""
    categories = _read_services_yaml_raw().get("categories", [])
    return categories if isinstance(categories, list) else []


def load_storage_mounts_config() -> list[dict[str, str]]:
    """Read optional physical storage mounts mapping from services.yaml."""
    mounts = _read_services_yaml_raw().get("storage_mounts", [])
    if not isinstance(mounts, list):
        return []
    return [m for m in mounts if isinstance(m, dict) and m.get("subpath")]
