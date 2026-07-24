"""
Configuration models and file handling for barista.

Handles reading/writing state.json and local.json files.
"""

from __future__ import annotations

import copy
import fcntl
import hashlib
import json
import os
import re
import subprocess
import tempfile
from collections.abc import Callable, Iterable, Mapping
from contextlib import ExitStack, contextmanager
from pathlib import Path
from typing import Any, Union

from pydantic import (
    BaseModel,
    ConfigDict,
    Field,
    ValidationError,
    field_validator,
)


STATE_VERSION = 2
MAX_SAVE_RETRIES = 5


class ConfigFileError(ValueError):
    """Raised when a configuration file cannot be read safely."""


class PreservingModel(BaseModel):
    """Typed UI view that retains state keys newer than this TUI."""

    model_config = ConfigDict(extra="allow", validate_assignment=True)


class AppearanceConfig(PreservingModel):
    """Appearance settings for the status bar."""
    theme: str = "default"
    bar_height: int = Field(default=28, ge=20, le=50)
    corner_radius: int = Field(default=0, ge=0, le=16)
    blur_radius: int = Field(default=30, ge=0, le=80)
    widget_scale: float = Field(default=1.0, ge=0.85, le=1.25)
    bar_color: str = "0xC021162F"
    clock_font_style: str = "Semibold"
    widget_corner_radius: int = Field(default=6, ge=0, le=16)
    font_icon: str = "Hack Nerd Font"
    font_text: str = "Source Code Pro"
    font_numbers: str = "SF Mono"
    popup_bg_color: str = "0xC021162F"
    popup_border_color: str = "0x60cdd6f4"
    menu_popup_bg_color: str = "0xE021162F"
    menu_font_style: str = "Bold"
    menu_header_font_style: str = "Bold"
    menu_font_size_offset: int = Field(default=1, ge=-2, le=6)

    @field_validator(
        "bar_color",
        "popup_bg_color",
        "popup_border_color",
        "menu_popup_bg_color",
    )
    @classmethod
    def validate_argb_color(cls, value: str) -> str:
        if re.fullmatch(r"0x[0-9A-Fa-f]{8}", value) is None:
            raise ValueError("color must use 0xAARRGGBB format")
        return value


class WidgetsConfig(PreservingModel):
    """Widget enable/disable settings."""
    clock: bool = True
    battery: bool = True
    volume: bool = True
    network: bool = True
    system_info: bool = True


class IconsConfig(PreservingModel):
    """Icon customization settings."""
    apple: str = ""
    quest: str = "󰊠"
    settings: str = ""
    clock: str = ""
    calendar: str = ""
    battery: str = ""
    wifi: str = "󰖩"
    volume: str = ""


class SystemInfoItemsConfig(PreservingModel):
    """System info popup items."""

    cpu: bool = False
    mem: bool = True
    disk: bool = True
    net: bool = True
    swap: bool = True
    uptime: bool = True
    procs: bool = True
    # Retained for legacy state compatibility; the runtime no longer renders it.
    docs: bool = True
    actions: bool = True


class TogglesConfig(PreservingModel):
    """Feature toggles."""
    yabai_shortcuts: bool = True


class IntegrationConfig(PreservingModel):
    """Base integration configuration."""
    enabled: bool = False


class YazeIntegration(IntegrationConfig):
    """Yaze ROM hacking integration."""
    enabled: bool = False
    recent_roms: list[str] = Field(default_factory=list)
    build_dir: str = "build/bin"


class EmacsIntegration(IntegrationConfig):
    """Emacs integration."""
    enabled: bool = False
    workspace_name: str = "Emacs"
    recent_org_files: list[str] = Field(default_factory=list)


class CortexIntegration(IntegrationConfig):
    """Cortex integration."""
    enabled: bool = False


class HalextIntegration(IntegrationConfig):
    """Halext-org integration."""
    enabled: bool = False
    server_url: str = ""
    api_key: str = ""
    sync_interval: int = 300
    show_tasks: bool = True
    show_calendar: bool = True
    show_suggestions: bool = True


class IntegrationsConfig(PreservingModel):
    """All integration settings."""
    yaze: YazeIntegration = Field(default_factory=YazeIntegration)
    emacs: EmacsIntegration = Field(default_factory=EmacsIntegration)
    cortex: CortexIntegration = Field(default_factory=CortexIntegration)
    halext: HalextIntegration = Field(default_factory=HalextIntegration)


class BaristaConfig(PreservingModel):
    """Main barista configuration (state.json)."""

    appearance: AppearanceConfig = Field(default_factory=AppearanceConfig)
    widgets: WidgetsConfig = Field(default_factory=WidgetsConfig)
    icons: IconsConfig = Field(default_factory=IconsConfig)
    system_info_items: SystemInfoItemsConfig = Field(default_factory=SystemInfoItemsConfig)
    toggles: TogglesConfig = Field(default_factory=TogglesConfig)
    integrations: IntegrationsConfig = Field(default_factory=IntegrationsConfig)
    # Lua encodes an empty table as [], so accept both JSON map representations.
    widget_colors: Union[dict[str, str], list[object]] = Field(default_factory=dict)
    space_icons: dict[str, str] = Field(default_factory=dict)
    space_modes: dict[str, str] = Field(default_factory=dict)
    spaces: dict[str, object] = Field(default_factory=lambda: {
        "creator_mode": "per_display",
        "right_click_close": "confirm",
        "reorder_mode": "menu",
        "modifier_reorder_enabled": True,
        "context_menu_on_right_click": True,
        "swap_indicator": True,
        "experimental_diff_updates": True,
    })
    menus: dict[str, object] = Field(default_factory=lambda: {
        "apple": {
            "show_missing": False,
            "items": {},
            "custom": {},
            "sections": {},
            "hover": {},
        },
        "work": {
            "google_apps": [],
            "apps_file": "data/work_apps.local.json",
            "workspace_domain": "",
        },
    })
    modes: dict[str, object] = Field(default_factory=lambda: {
        "window_manager": "auto",
        "runtime_backend": "auto",
    })
    
    # Custom paths (machine-specific)
    paths: dict[str, str] = Field(default_factory=dict)


class LocalConfig(PreservingModel):
    """Machine-specific local configuration (local.json)."""
    machine: str = ""
    paths: dict[str, str] = Field(default_factory=lambda: {
        "code": os.path.expanduser(os.getenv("BARISTA_CODE_DIR", "~/src")),
        "scripts": os.path.expanduser(os.getenv("BARISTA_SCRIPTS_DIR", "~/.config/sketchybar/scripts")),
    })
    integrations: dict[str, dict] = Field(default_factory=dict)


# Available themes
THEMES = [
    "default",
    "dracula",
    "espresso",
    "gruvbox",
    "kanagawa",
    "mocha",
    "nord",
    "rosepine",
    "solarized",
    "tokyo_night",
    "chocolate",
    "caramel",
    "white_coffee",
    "strawberry_matcha",
    "halext",
]

# Space layout modes
SPACE_MODES = ["float", "bsp", "stack"]


def get_config_dir() -> Path:
    """Get the barista config directory."""
    config_dir = os.environ.get("BARISTA_CONFIG_DIR")
    if config_dir:
        return Path(config_dir)
    return Path.home() / ".config" / "sketchybar"


def get_state_file() -> Path:
    """Get the state.json file path."""
    return get_config_dir() / "state.json"


def get_local_file() -> Path:
    """Get the local.json file path."""
    return get_config_dir() / "local.json"


def _resolve_path(path: Path | str | None, default: Path) -> Path:
    if path is None:
        return default
    return Path(path).expanduser()


def _load_raw_object_with_token(
    path: Path,
) -> tuple[dict[str, Any], str | None]:
    """Read one complete JSON snapshot and its content token."""
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return {}, None
    except OSError as exc:
        raise ConfigFileError(f"Could not read {path}: {exc}") from exc

    token = hashlib.sha256(raw).hexdigest()
    try:
        data = json.loads(raw)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConfigFileError(f"Could not read {path}: {exc}") from exc

    if not isinstance(data, dict):
        raise ConfigFileError(f"Could not read {path}: top-level JSON must be an object")
    return data, token


def _load_raw_object(path: Path) -> dict[str, Any]:
    """Read a JSON object without inventing defaults on parse failure."""
    data, _ = _load_raw_object_with_token(path)
    return data


def load_config_document(state_file: Path | str | None = None) -> dict[str, Any]:
    """Load the raw state document for lossless previews and patching."""
    path = _resolve_path(state_file, get_state_file())
    return _load_raw_object(path)


def load_config_document_snapshot(
    state_file: Path | str | None = None,
) -> tuple[dict[str, Any], str | None]:
    """Load one raw state snapshot and its exact content token."""
    path = _resolve_path(state_file, get_state_file())
    return _load_raw_object_with_token(path)


def _normalize_empty_map_views(
    data: dict[str, Any],
    map_keys: tuple[str, ...],
) -> dict[str, Any]:
    """Normalize Lua's [] encoding only in the typed UI view."""
    view = copy.deepcopy(data)
    for key in map_keys:
        if view.get(key) == []:
            view[key] = {}

    integrations = view.get("integrations")
    if isinstance(integrations, dict):
        for key, value in integrations.items():
            if value == []:
                integrations[key] = {}
    return view


def validate_config_document(
    data: dict[str, Any],
    state_file: Path | str | None = None,
) -> BaristaConfig:
    """Validate one already-read state snapshot as the TUI's typed view."""
    path = _resolve_path(state_file, get_state_file())
    view = _normalize_empty_map_views(
        data,
        (
            "appearance",
            "widgets",
            "icons",
            "system_info_items",
            "toggles",
            "integrations",
            "space_icons",
            "space_modes",
            "spaces",
            "menus",
            "modes",
            "paths",
        ),
    )
    try:
        return BaristaConfig.model_validate(view)
    except ValidationError as exc:
        raise ConfigFileError(f"Could not validate {path}: {exc}") from exc


def load_config(state_file: Path | str | None = None) -> BaristaConfig:
    """Load state.json as a typed view while preserving its raw document."""
    path = _resolve_path(state_file, get_state_file())
    return validate_config_document(_load_raw_object(path), path)


class _PatchMarker:
    def __deepcopy__(self, memo: dict[int, object]) -> "_PatchMarker":
        return self


_NO_CHANGE = _PatchMarker()


def _diff_value(before: Any, after: Any) -> Any:
    if before == after:
        return _NO_CHANGE
    if isinstance(before, Mapping) and isinstance(after, Mapping):
        patch: dict[str, Any] = {}
        for key, value in after.items():
            if key not in before:
                patch[key] = copy.deepcopy(value)
                continue
            nested = _diff_value(before[key], value)
            if nested is not _NO_CHANGE:
                patch[key] = nested
        return patch if patch else _NO_CHANGE
    return copy.deepcopy(after)


def build_config_patch(
    before: Mapping[str, Any] | BaseModel,
    after: Mapping[str, Any] | BaseModel,
) -> dict[str, Any]:
    """Build a recursive patch containing only changed UI values."""
    before_values = (
        before.model_dump(exclude_none=True)
        if isinstance(before, BaseModel)
        else before
    )
    after_values = (
        after.model_dump(exclude_none=True)
        if isinstance(after, BaseModel)
        else after
    )
    patch = _diff_value(before_values, after_values)
    if patch is _NO_CHANGE:
        return {}
    if not isinstance(patch, dict):
        raise TypeError("Configuration snapshots must be mappings")
    return patch


def _deep_merge(base: dict[str, Any], patch: Mapping[str, Any]) -> dict[str, Any]:
    result = copy.deepcopy(base)
    for key, value in patch.items():
        if isinstance(value, Mapping) and isinstance(result.get(key), dict):
            result[key] = _deep_merge(result[key], value)
        elif isinstance(value, Mapping):
            result[key] = _deep_merge({}, value)
        else:
            result[key] = copy.deepcopy(value)
    return result


def _file_token(path: Path) -> str | None:
    try:
        raw = path.read_bytes()
    except FileNotFoundError:
        return None
    except OSError as exc:
        raise ConfigFileError(f"Could not inspect {path}: {exc}") from exc
    return hashlib.sha256(raw).hexdigest()


def _atomic_write_bytes(
    path: Path,
    data: bytes,
    *,
    expected_token: str | None | _PatchMarker = _NO_CHANGE,
) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temp_name = tempfile.mkstemp(
        dir=path.parent,
        prefix=f".{path.name}.",
        suffix=".tmp",
    )
    temp_path = Path(temp_name)
    try:
        with os.fdopen(descriptor, "wb") as file:
            file.write(data)
            file.flush()
            os.fsync(file.fileno())
        if (
            expected_token is not _NO_CHANGE
            and _file_token(path) != expected_token
        ):
            temp_path.unlink(missing_ok=True)
            return False
        os.replace(temp_path, path)
        return True
    except Exception:
        temp_path.unlink(missing_ok=True)
        raise


def _serialize_json(data: Any) -> bytes:
    return (
        json.dumps(data, indent=2, ensure_ascii=False) + "\n"
    ).encode("utf-8")


def _atomic_write_json(
    path: Path,
    data: Any,
    *,
    expected_token: str | None | _PatchMarker = _NO_CHANGE,
) -> bool:
    return _atomic_write_bytes(
        path,
        _serialize_json(data),
        expected_token=expected_token,
    )


@contextmanager
def _config_lock(path: Path):
    """Serialize read-merge-replace cycles for one canonical config path."""
    lock_root = (
        Path(tempfile.gettempdir())
        / f"barista-config-locks-{os.getuid()}"
    )
    lock_root.mkdir(mode=0o700, parents=True, exist_ok=True)
    canonical_path = str(path.resolve(strict=False))
    lock_name = hashlib.sha256(canonical_path.encode("utf-8")).hexdigest()
    lock_path = lock_root / f"{lock_name}.lock"

    with lock_path.open("a+", encoding="utf-8") as lock_file:
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
        try:
            yield
        finally:
            fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)


@contextmanager
def config_write_locks(paths: Iterable[Path | str]):
    """Lock multiple config paths in one canonical order."""
    canonical_paths = sorted(
        {
            Path(path).expanduser().resolve(strict=False)
            for path in paths
        },
        key=str,
    )
    with ExitStack() as stack:
        for path in canonical_paths:
            stack.enter_context(_config_lock(path))
        yield


@contextmanager
def config_write_lock(state_file: Path | str | None = None):
    """Hold the TUI writer lock for a complete state-side-effect transaction."""
    path = _resolve_path(state_file, get_state_file())
    with config_write_locks((path,)):
        yield


def _save_json_document_locked(target: Path, data: Any) -> str:
    serialized = _serialize_json(data)
    written_token = hashlib.sha256(serialized).hexdigest()
    for _ in range(MAX_SAVE_RETRIES):
        token = _file_token(target)
        if _atomic_write_bytes(
            target,
            serialized,
            expected_token=token,
        ):
            return written_token
    raise ConfigFileError(f"Could not save {target}: file changed repeatedly")


def save_json_document(
    path: Path | str,
    data: Any,
    *,
    acquire_lock: bool = True,
) -> str:
    """Atomically replace a derived JSON document with bounded CAS retries."""
    target = Path(path).expanduser()
    if acquire_lock:
        with _config_lock(target):
            return _save_json_document_locked(target, data)
    return _save_json_document_locked(target, data)


def _read_json_array_snapshot(
    path: Path,
) -> tuple[bytes | None, str | None, list[Any]]:
    try:
        content = path.read_bytes()
    except FileNotFoundError:
        return None, None, []
    except OSError as exc:
        raise ConfigFileError(f"Could not read {path}: {exc}") from exc

    token = hashlib.sha256(content).hexdigest()
    try:
        data = json.loads(content)
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise ConfigFileError(f"Could not read {path}: {exc}") from exc
    if not isinstance(data, list):
        raise ConfigFileError(
            f"Could not read {path}: top-level JSON must be an array"
        )
    return content, token, data


def _update_json_array_document_locked(
    target: Path,
    transform: Callable[[list[Any]], list[Any]],
) -> tuple[bytes | None, list[Any], str]:
    for _ in range(MAX_SAVE_RETRIES):
        previous_content, token, current = _read_json_array_snapshot(target)
        updated = transform(copy.deepcopy(current))
        if not isinstance(updated, list):
            raise TypeError("JSON array transform must return a list")
        serialized = _serialize_json(updated)
        written_token = hashlib.sha256(serialized).hexdigest()
        if _atomic_write_bytes(
            target,
            serialized,
            expected_token=token,
        ):
            return previous_content, updated, written_token
    raise ConfigFileError(f"Could not save {target}: file changed repeatedly")


def update_json_array_document(
    path: Path | str,
    transform: Callable[[list[Any]], list[Any]],
    *,
    acquire_lock: bool = True,
) -> tuple[bytes | None, list[Any], str]:
    """Run a lossless JSON-array read/transform/write cycle."""
    target = Path(path).expanduser()
    if acquire_lock:
        with _config_lock(target):
            return _update_json_array_document_locked(target, transform)
    return _update_json_array_document_locked(target, transform)


def restore_file_snapshot(
    path: Path | str,
    content: bytes | None,
    *,
    expected_token: str,
    acquire_lock: bool = True,
) -> bool:
    """Restore exact bytes if a derived file still contains our last write."""
    target = Path(path).expanduser()

    def restore() -> bool:
        if _file_token(target) != expected_token:
            return False
        if content is None:
            target.unlink(missing_ok=True)
            return True
        return _atomic_write_bytes(
            target,
            content,
            expected_token=expected_token,
        )

    if acquire_lock:
        with _config_lock(target):
            return restore()
    return restore()


def _save_config_locked(
    config: BaristaConfig,
    updates: Mapping[str, Any] | None,
    path: Path,
) -> None:
    for _ in range(MAX_SAVE_RETRIES):
        base, token = _load_raw_object_with_token(path)
        existing_version = base.get("_version", _NO_CHANGE)

        if updates is None:
            patch: Mapping[str, Any] = config.model_dump(exclude_none=True)
        else:
            patch = updates

        data = _deep_merge(base, patch)
        if existing_version is not _NO_CHANGE:
            data["_version"] = existing_version
        else:
            data.setdefault("_version", STATE_VERSION)

        if token is not None and data == base:
            return
        if _atomic_write_json(path, data, expected_token=token):
            return
    raise ConfigFileError(f"Could not save {path}: file changed repeatedly")


def save_config(
    config: BaristaConfig,
    *,
    updates: Mapping[str, Any] | None = None,
    state_file: Path | str | None = None,
    acquire_lock: bool = True,
) -> None:
    """Patch state.json without deleting keys the TUI does not expose."""
    path = _resolve_path(state_file, get_state_file())
    if acquire_lock:
        with _config_lock(path):
            _save_config_locked(config, updates, path)
    else:
        _save_config_locked(config, updates, path)


def save_config_if_unchanged(
    config: BaristaConfig,
    *,
    updates: Mapping[str, Any] | None,
    state_file: Path | str | None,
    expected_token: str | None,
    acquire_lock: bool = True,
) -> bool:
    """Patch one exact state snapshot, returning false if it changed."""
    path = _resolve_path(state_file, get_state_file())

    def save() -> bool:
        base, token = _load_raw_object_with_token(path)
        if token != expected_token:
            return False
        existing_version = base.get("_version", _NO_CHANGE)
        patch: Mapping[str, Any] = (
            config.model_dump(exclude_none=True)
            if updates is None
            else updates
        )
        data = _deep_merge(base, patch)
        if existing_version is not _NO_CHANGE:
            data["_version"] = existing_version
        else:
            data.setdefault("_version", STATE_VERSION)
        if token is not None and data == base:
            return True
        return _atomic_write_json(path, data, expected_token=token)

    if acquire_lock:
        with _config_lock(path):
            return save()
    return save()


def load_local_config(local_file: Path | str | None = None) -> LocalConfig:
    """Load machine-local configuration without hiding parse failures."""
    path = _resolve_path(local_file, get_local_file())
    data = _load_raw_object(path)
    view = _normalize_empty_map_views(data, ("paths", "integrations"))
    try:
        return LocalConfig.model_validate(view)
    except ValidationError as exc:
        raise ConfigFileError(f"Could not validate {path}: {exc}") from exc


def save_local_config(
    config: LocalConfig,
    *,
    updates: Mapping[str, Any] | None = None,
    local_file: Path | str | None = None,
) -> None:
    """Patch local.json without deleting unknown machine-local keys."""
    path = _resolve_path(local_file, get_local_file())
    with _config_lock(path):
        for _ in range(MAX_SAVE_RETRIES):
            base, token = _load_raw_object_with_token(path)
            if updates is None:
                patch: Mapping[str, Any] = config.model_dump(exclude_none=True)
            else:
                patch = updates
            data = _deep_merge(base, patch)
            if token is None and not data:
                return
            if token is not None and data == base:
                return
            if _atomic_write_json(path, data, expected_token=token):
                return
        raise ConfigFileError(f"Could not save {path}: file changed repeatedly")


def reload_sketchybar(config_dir: Path | str | None = None) -> bool:
    """Reload through Barista's serialized, health-checked helper."""
    directory = _resolve_path(config_dir, get_config_dir()).resolve(strict=False)
    helper = directory / "plugins" / "reload_sketchybar.sh"
    if not helper.is_file() or not os.access(helper, os.X_OK):
        return False

    environment = os.environ.copy()
    environment["CONFIG_DIR"] = str(directory)
    environment["BARISTA_CONFIG_DIR"] = str(directory)
    try:
        subprocess.run(
            [str(helper)],
            check=True,
            capture_output=True,
            text=True,
            env=environment,
        )
        return True
    except (OSError, subprocess.CalledProcessError):
        return False


def parse_color(color_str: str) -> tuple[int, int, int, int]:
    """Parse ARGB hex color string to (a, r, g, b) tuple."""
    # Remove 0x prefix if present
    if color_str.startswith("0x"):
        color_str = color_str[2:]
    
    # Parse as hex
    try:
        value = int(color_str, 16)
        a = (value >> 24) & 0xFF
        r = (value >> 16) & 0xFF
        g = (value >> 8) & 0xFF
        b = value & 0xFF
        return (a, r, g, b)
    except ValueError:
        return (192, 33, 22, 47)  # Default color


def format_color(a: int, r: int, g: int, b: int) -> str:
    """Format ARGB tuple to hex color string."""
    return f"0x{a:02X}{r:02X}{g:02X}{b:02X}"
