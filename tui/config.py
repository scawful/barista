"""
Configuration models and file handling for barista.

Handles reading/writing state.json and local.json files.
"""

import json
import os
from pathlib import Path
from typing import Optional
from pydantic import BaseModel, Field


class AppearanceConfig(BaseModel):
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


class WidgetsConfig(BaseModel):
    """Widget enable/disable settings."""
    clock: bool = True
    battery: bool = True
    volume: bool = True
    network: bool = True
    system_info: bool = True


class IconsConfig(BaseModel):
    """Icon customization settings."""
    apple: str = ""
    quest: str = "󰊠"
    settings: str = ""
    clock: str = ""
    calendar: str = ""
    battery: str = ""
    wifi: str = "󰖩"
    volume: str = ""


class SystemInfoItemsConfig(BaseModel):
    """System info popup items."""
    cpu: bool = True
    mem: bool = True
    disk: bool = True
    net: bool = True
    docs: bool = True
    actions: bool = True


class TogglesConfig(BaseModel):
    """Feature toggles."""
    yabai_shortcuts: bool = True


class IntegrationConfig(BaseModel):
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


class GoogleIntegration(IntegrationConfig):
    """Google workspace integration."""
    enabled: bool = False


class IntegrationsConfig(BaseModel):
    """All integration settings."""
    yaze: YazeIntegration = Field(default_factory=YazeIntegration)
    emacs: EmacsIntegration = Field(default_factory=EmacsIntegration)
    cortex: CortexIntegration = Field(default_factory=CortexIntegration)
    halext: HalextIntegration = Field(default_factory=HalextIntegration)
    google: GoogleIntegration = Field(default_factory=GoogleIntegration)


class BaristaConfig(BaseModel):
    """Main barista configuration (state.json)."""
    _version: int = 1
    appearance: AppearanceConfig = Field(default_factory=AppearanceConfig)
    widgets: WidgetsConfig = Field(default_factory=WidgetsConfig)
    icons: IconsConfig = Field(default_factory=IconsConfig)
    system_info_items: SystemInfoItemsConfig = Field(default_factory=SystemInfoItemsConfig)
    toggles: TogglesConfig = Field(default_factory=TogglesConfig)
    integrations: IntegrationsConfig = Field(default_factory=IntegrationsConfig)
    widget_colors: list = Field(default_factory=list)
    space_icons: dict[str, str] = Field(default_factory=dict)
    space_modes: dict[str, str] = Field(default_factory=dict)
    
    # Custom paths (machine-specific)
    paths: dict[str, str] = Field(default_factory=dict)


class LocalConfig(BaseModel):
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
    "espresso", 
    "mocha",
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


def load_config() -> BaristaConfig:
    """Load configuration from state.json."""
    state_file = get_state_file()
    
    if state_file.exists():
        try:
            with open(state_file) as f:
                data = json.load(f)
            return BaristaConfig.model_validate(data)
        except (json.JSONDecodeError, Exception) as e:
            print(f"Warning: Could not load state.json: {e}")
    
    return BaristaConfig()


def save_config(config: BaristaConfig) -> None:
    """Save configuration to state.json."""
    state_file = get_state_file()
    
    # Ensure directory exists
    state_file.parent.mkdir(parents=True, exist_ok=True)
    
    # Convert to dict, handling the _version field
    data = config.model_dump(exclude_none=True)
    data["_version"] = 1
    
    # Write atomically (temp file + rename)
    temp_file = state_file.with_suffix(".tmp")
    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    temp_file.rename(state_file)


def load_local_config() -> LocalConfig:
    """Load local configuration from local.json."""
    local_file = get_local_file()
    
    if local_file.exists():
        try:
            with open(local_file) as f:
                data = json.load(f)
            return LocalConfig.model_validate(data)
        except (json.JSONDecodeError, Exception) as e:
            print(f"Warning: Could not load local.json: {e}")
    
    return LocalConfig()


def save_local_config(config: LocalConfig) -> None:
    """Save local configuration to local.json."""
    local_file = get_local_file()
    
    local_file.parent.mkdir(parents=True, exist_ok=True)
    
    data = config.model_dump(exclude_none=True)
    
    temp_file = local_file.with_suffix(".tmp")
    with open(temp_file, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
    temp_file.rename(local_file)


def reload_sketchybar() -> bool:
    """Reload sketchybar configuration."""
    import subprocess
    try:
        subprocess.run(["sketchybar", "--reload"], check=True, capture_output=True)
        return True
    except (subprocess.CalledProcessError, FileNotFoundError):
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
