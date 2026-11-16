"""Configuration loader and hot-reload writer for .env and services.yaml."""

import errno
from functools import lru_cache
import os
from pathlib import Path
import re
import shutil
import tempfile
from typing import Any

import yaml
from pydantic_settings import BaseSettings, SettingsConfigDict

SECRET_ENV_KEYS = frozenset(
    {
        "PVE_TOKEN_SECRET",
        "JELLYFIN_API_KEY",
        "JELLYSEERR_API_KEY",
        "PLEX_TOKEN",
        "RADARR_API_KEY",
        "SONARR_API_KEY",
        "PROWLARR_API_KEY",
        "QBIT_PASSWORD",
    }
)

_ENV_LINE_RE = re.compile(r"^\s*(?:export\s+)?([A-Za-z_][A-Za-z0-9_]*)\s*=.*$")
_TRANSIENT_SERVICE_KEYS = frozenset({"online", "latency_ms", "status_code"})


def resolve_env_file() -> Path:
    """Locate .env file prioritizing /app/.env in Docker, then project root."""
    candidates = [
        Path("/app/.env"),
        Path.cwd() / ".env",
        Path.cwd().parent / ".env",
        Path(__file__).resolve().parents[2] / ".env",
    ]
    for path in candidates:
        if path.is_file():
            return path
    if Path("/app").is_dir():
        return Path("/app/.env")
    return Path(__file__).resolve().parents[2] / ".env"


def _find_env_file() -> str | None:
    """Return existing .env path string for pydantic-settings default model_config."""
    path = resolve_env_file()
    return str(path) if path.is_file() else None


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
        if Path("/app/services.yaml").is_file() or Path("/app").is_dir():
            return Path("/app/services.yaml")
        return project_root

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
    return Settings(_env_file=resolve_env_file())


def reload_settings() -> Settings:
    """Clear cached settings and reload from .env and environment."""
    get_settings.cache_clear()
    return get_settings()


def is_secret_configured(value: str | None) -> bool:
    """Return True when a secret string is set and not an example placeholder."""
    cleaned = (value or "").strip()
    return bool(cleaned) and not cleaned.startswith("replace-with-")


def is_configured(settings: Settings | None = None) -> bool:
    """Return True when Proxmox host and API token secret are configured."""
    cfg = settings or get_settings()
    host = cfg.pve_host.strip()
    secret = cfg.pve_token_secret.strip()
    return bool(host) and bool(secret) and secret != "replace-with-pve-token-secret"


def _write_text_safe(
    path: Path, content: str, new_file_mode: int | None = None
) -> None:
    """Write text atomically, falling back to in-place write on bind-mounted files."""
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp_path: Path | None = None
    try:
        with tempfile.NamedTemporaryFile(
            mode="w",
            encoding="utf-8",
            dir=path.parent,
            prefix=f".{path.name}.",
            suffix=".tmp",
            delete=False,
        ) as tmp_file:
            tmp_path = Path(tmp_file.name)
            tmp_file.write(content)
            tmp_file.flush()
            os.fsync(tmp_file.fileno())

        if path.exists():
            shutil.copymode(path, tmp_path)
        elif new_file_mode is not None:
            os.chmod(tmp_path, new_file_mode)

        os.replace(tmp_path, path)
        tmp_path = None
    except OSError as exc:
        if exc.errno not in {errno.EBUSY, errno.EXDEV, errno.EPERM}:
            raise
        with path.open("w", encoding="utf-8") as fh:
            fh.write(content)
            fh.flush()
            os.fsync(fh.fileno())
        if new_file_mode is not None and not path.exists():
            os.chmod(path, new_file_mode)
    finally:
        if tmp_path is not None and tmp_path.exists():
            try:
                tmp_path.unlink()
            except OSError:
                pass


def _format_env_value(raw: str) -> str:
    """Format a scalar string for .env, quoting only when needed."""
    if any(ch.isspace() or ch in {"#", '"', "'", "$"} for ch in raw):
        escaped = raw.replace("\\", "\\\\").replace('"', '\\"')
        return f'"{escaped}"'
    return raw


def update_env_file(updates: dict[str, Any]) -> Path:
    """Atomically update known Settings keys in .env while preserving comments."""
    env_path = resolve_env_file()
    allowed_keys = {field.upper() for field in Settings.model_fields}

    normalized: dict[str, str] = {}
    for raw_key, raw_val in updates.items():
        env_key = str(raw_key).strip().upper()
        if env_key not in allowed_keys or raw_val is None:
            continue
        if isinstance(raw_val, bool):
            str_val = "true" if raw_val else "false"
        else:
            str_val = str(raw_val).replace("\r", "").replace("\n", "")
            if env_key not in SECRET_ENV_KEYS:
                str_val = str_val.strip()

        if env_key in SECRET_ENV_KEYS and str_val.strip() == "":
            continue
        normalized[env_key] = str_val

    existing_lines = (
        env_path.read_text(encoding="utf-8").splitlines() if env_path.is_file() else []
    )
    if not normalized and env_path.is_file():
        return env_path

    new_lines: list[str] = []
    written_keys: set[str] = set()
    for line in existing_lines:
        match = _ENV_LINE_RE.match(line)
        if not match:
            new_lines.append(line)
            continue
        key = match.group(1)
        if key in normalized:
            if key not in written_keys:
                new_lines.append(f"{key}={_format_env_value(normalized[key])}")
                written_keys.add(key)
        else:
            new_lines.append(line)

    for key, val in normalized.items():
        if key not in written_keys:
            new_lines.append(f"{key}={_format_env_value(val)}")
            written_keys.add(key)

    rendered = "\n".join(new_lines) + ("\n" if new_lines else "")
    _write_text_safe(env_path, rendered, new_file_mode=0o600)

    # Docker env_file seeds os.environ at container startup, which overrides .env in pydantic-settings.
    for key, val in normalized.items():
        os.environ[key] = val

    return env_path


def _sanitize_categories(categories: list[dict[str, Any]]) -> list[dict[str, Any]]:
    cleaned: list[dict[str, Any]] = []
    for cat in categories:
        if not isinstance(cat, dict):
            continue
        raw_services = cat.get("services") or []
        services_list: list[dict[str, Any]] = []
        for svc in raw_services:
            if not isinstance(svc, dict):
                continue
            item = {
                k: v
                for k, v in svc.items()
                if k not in _TRANSIENT_SERVICE_KEYS and v is not None
            }
            if item.get("widget") == "":
                item.pop("widget", None)
            services_list.append(item)
        cleaned.append({"name": str(cat.get("name") or "Services"), "services": services_list})
    return cleaned


def _sanitize_storage_mounts(mounts: list[dict[str, Any]]) -> list[dict[str, str]]:
    cleaned: list[dict[str, str]] = []
    for mount in mounts:
        if not isinstance(mount, dict):
            continue
        subpath = str(mount.get("subpath") or "").strip()
        if not subpath:
            continue
        cleaned.append(
            {
                "mount": str(mount.get("mount") or f"/mnt/{subpath}").strip(),
                "subpath": subpath,
                "wwn": str(mount.get("wwn") or "").strip(),
                "label": str(mount.get("label") or f"Disque {subpath}").strip(),
            }
        )
    return cleaned


def save_services_yaml(
    categories: list[dict[str, Any]] | None = None,
    storage_mounts: list[dict[str, Any]] | None = None,
) -> Path:
    """Save services.yaml cleanly while preserving any unmodified section."""
    yaml_path = get_settings().resolve_services_yaml()
    existing = dict(_read_services_yaml_raw())

    if categories is not None:
        existing["categories"] = _sanitize_categories(categories)
    if storage_mounts is not None:
        existing["storage_mounts"] = _sanitize_storage_mounts(storage_mounts)

    ordered: dict[str, Any] = {}
    for preferred_key in ("categories", "storage_mounts"):
        if preferred_key in existing:
            ordered[preferred_key] = existing.pop(preferred_key)
    ordered.update(existing)

    rendered = yaml.safe_dump(
        ordered,
        allow_unicode=True,
        sort_keys=False,
        default_flow_style=False,
        indent=2,
    )
    _write_text_safe(yaml_path, rendered)
    return yaml_path


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
