"""Integrations tab - integration toggles and paths."""

from __future__ import annotations

import os

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, Label, Switch, Input

from ..config import BaristaConfig, LocalConfig


class IntegrationToggle(Horizontal):
    """Toggle for an integration with description."""
    
    DEFAULT_CSS = """
    IntegrationToggle {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    IntegrationToggle Label {
        width: 16;
    }
    
    IntegrationToggle Switch {
        width: auto;
    }
    
    IntegrationToggle .int-desc {
        color: $text-muted;
        padding-left: 2;
    }
    """
    
    def __init__(self, name: str, enabled: bool, description: str, int_id: str, **kwargs):
        super().__init__(**kwargs)
        self.int_name = name
        self.enabled = enabled
        self.description = description
        self.int_id = int_id
    
    def compose(self) -> ComposeResult:
        yield Label(self.int_name)
        yield Switch(value=self.enabled, id=self.int_id)
        yield Static(self.description, classes="int-desc")


class PathInput(Horizontal):
    """Input for a custom path."""
    
    DEFAULT_CSS = """
    PathInput {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    PathInput Label {
        width: 16;
    }
    
    PathInput Input {
        width: 50;
    }
    """
    
    def __init__(self, name: str, path: str, path_id: str, **kwargs):
        super().__init__(**kwargs)
        self.path_name = name
        self.path = path
        self.path_id = path_id
    
    def compose(self) -> ComposeResult:
        yield Label(self.path_name)
        yield Input(self.path, id=self.path_id, placeholder="path")


class IntegrationsTab(Vertical):
    """Integrations configuration tab."""
    
    DEFAULT_CSS = """
    IntegrationsTab {
        padding: 1 2;
    }
    
    IntegrationsTab .section-header {
        text-style: bold;
        padding: 1 0;
        color: $accent;
    }
    
    IntegrationsTab .help-text {
        color: $text-muted;
        padding: 0 1 1 1;
    }
    """
    
    INTEGRATION_INFO = {
        "yaze": ("Yaze", "ROM hacking editor integration"),
        "emacs": ("Emacs", "Emacs org-mode integration"),
        "cortex": ("Cortex", "AFS + training dashboard integration"),
        "halext": ("Halext", "halext-org task management"),
    }
    
    DEFAULT_PATHS = {
        "code_dir": ("Code Directory", os.getenv("BARISTA_CODE_DIR", "~/src")),
        "scripts_dir": (
            "Scripts Directory",
            os.getenv("BARISTA_SCRIPTS_DIR", "~/.config/sketchybar/scripts"),
        ),
    }

    PATH_ALIASES = {
        "code_dir": ("code_dir", "code"),
        "scripts_dir": ("scripts_dir", "scripts"),
    }
    
    def __init__(
        self,
        config: BaristaConfig,
        local_config: LocalConfig | None = None,
        **kwargs,
    ):
        super().__init__(**kwargs)
        self.config = config
        self.local_config = local_config or LocalConfig()
        self.custom_path_ids: dict[str, str] = {}
    
    def compose(self) -> ComposeResult:
        self.custom_path_ids = {}
        yield Static("Integrations", classes="section-header")
        yield Static(
            "Enable or disable integrations with external tools.",
            classes="help-text"
        )
        
        integrations = self.config.integrations
        
        for int_key, (name, desc) in self.INTEGRATION_INFO.items():
            int_config = getattr(integrations, int_key, None)
            enabled = int_config.enabled if int_config else False
            yield IntegrationToggle(
                name=name,
                enabled=enabled,
                description=desc,
                int_id=f"int_{int_key}"
            )
        
        yield Static("Custom Paths", classes="section-header")
        yield Static(
            "Configure custom paths for your machine. "
            "Scripts default to ~/.config/sketchybar/scripts unless overridden.",
            classes="help-text"
        )
        
        # Runtime paths live in ignored state.json; local.json is a legacy fallback.
        for path_key, (name, default) in self.DEFAULT_PATHS.items():
            aliases = self.PATH_ALIASES[path_key]
            current = next(
                (
                    source[alias]
                    for source in (self.config.paths, self.local_config.paths)
                    for alias in aliases
                    if source.get(alias)
                ),
                default,
            )
            yield PathInput(
                name=name,
                path=current,
                path_id=f"path_{path_key}"
            )
        
        # Additional custom paths from config
        custom_index = 0
        for path_key, path_value in self.config.paths.items():
            if not any(
                path_key in aliases
                for aliases in self.PATH_ALIASES.values()
            ):
                input_id = f"path_custom_{custom_index}"
                custom_index += 1
                self.custom_path_ids[path_key] = input_id
                yield PathInput(
                    name=path_key.replace("_", " ").title(),
                    path=path_value,
                    path_id=input_id,
                )
    
    def get_values(self) -> dict:
        """Get current integration and path values."""
        values = {
            "integrations": {},
            "paths": {}
        }
        
        # Integration toggles
        for int_key in self.INTEGRATION_INFO.keys():
            try:
                switch = self.query_one(f"#int_{int_key}", Switch)
                values["integrations"][int_key] = {"enabled": switch.value}
            except Exception:
                pass
        
        # Paths
        for path_key in self.DEFAULT_PATHS:
            try:
                inp = self.query_one(f"#path_{path_key}", Input)
                values["paths"][path_key] = inp.value
            except Exception:
                pass

        for path_key, input_id in self.custom_path_ids.items():
            try:
                inp = self.query_one(f"#{input_id}", Input)
                values["paths"][path_key] = inp.value
            except Exception:
                pass
        
        return values
