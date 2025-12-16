"""Integrations tab - integration toggles and paths."""

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, Label, Switch, Input

from ..config import BaristaConfig, load_local_config, LocalConfig


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
        "halext": ("Halext", "halext-org task management"),
        "google": ("Google", "Google Workspace integration"),
    }
    
    DEFAULT_PATHS = {
        "code": ("Code Directory", "~/Code"),
        "scripts": ("Scripts Directory", "~/.config/scripts"),
    }
    
    def __init__(self, config: BaristaConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
        self.local_config = load_local_config()
    
    def compose(self) -> ComposeResult:
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
            "These override defaults.",
            classes="help-text"
        )
        
        # Default paths from local config
        for path_key, (name, default) in self.DEFAULT_PATHS.items():
            current = self.local_config.paths.get(path_key, default)
            yield PathInput(
                name=name,
                path=current,
                path_id=f"path_{path_key}"
            )
        
        # Additional custom paths from config
        for path_key, path_value in self.config.paths.items():
            if path_key not in self.DEFAULT_PATHS:
                yield PathInput(
                    name=path_key.replace("_", " ").title(),
                    path=path_value,
                    path_id=f"path_{path_key}"
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
        for path_key in list(self.DEFAULT_PATHS.keys()) + list(self.config.paths.keys()):
            try:
                inp = self.query_one(f"#path_{path_key}", Input)
                if inp.value:
                    values["paths"][path_key] = inp.value
            except Exception:
                pass
        
        return values
