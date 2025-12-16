"""Main Barista TUI application."""

import json
from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.widgets import (
    Header, Footer, Button, Static, TabbedContent, TabPane,
)

from .config import (
    BaristaConfig, load_config, save_config,
    load_local_config, save_local_config,
    reload_sketchybar, get_state_file,
)
from .screens import (
    GeneralTab, WidgetsTab, SpacesTab,
    IconsTab, IntegrationsTab, AdvancedTab,
)


class BaristaApp(App):
    """Barista configuration TUI."""
    
    CSS_PATH = "styles/app.tcss"
    
    BINDINGS = [
        Binding("ctrl+s", "save", "Save"),
        Binding("ctrl+r", "save_reload", "Save & Reload"),
        Binding("ctrl+q", "quit", "Quit"),
        Binding("escape", "quit", "Quit"),
        Binding("f1", "help", "Help"),
    ]
    
    TITLE = "barista"
    SUB_TITLE = "SketchyBar Configuration"
    
    def __init__(self, config_path: str | None = None):
        super().__init__()
        self.config_path = config_path
        self.config: BaristaConfig = load_config()
        self.local_config = load_local_config()
        self.dirty = False
    
    def compose(self) -> ComposeResult:
        yield Header()
        
        with Vertical(id="main-container"):
            with TabbedContent():
                with TabPane("General", id="tab-general"):
                    yield GeneralTab(self.config)
                
                with TabPane("Widgets", id="tab-widgets"):
                    yield WidgetsTab(self.config)
                
                with TabPane("Spaces", id="tab-spaces"):
                    yield SpacesTab(self.config)
                
                with TabPane("Icons", id="tab-icons"):
                    yield IconsTab(self.config)
                
                with TabPane("Integrations", id="tab-integrations"):
                    yield IntegrationsTab(self.config)
                
                with TabPane("Advanced", id="tab-advanced"):
                    raw_json = json.dumps(
                        self.config.model_dump(exclude_none=True),
                        indent=2
                    )
                    yield AdvancedTab(self.config, raw_json)
            
            with Horizontal(id="button-bar"):
                yield Button("Save", id="btn-save", variant="primary")
                yield Button("Save & Reload", id="btn-save-reload", variant="success")
                yield Button("Cancel", id="btn-cancel", variant="default")
            
            yield Static(f"Config: {get_state_file()}", id="status-bar")
        
        yield Footer()
    
    def on_button_pressed(self, event: Button.Pressed) -> None:
        """Handle button presses."""
        if event.button.id == "btn-save":
            self.action_save()
        elif event.button.id == "btn-save-reload":
            self.action_save_reload()
        elif event.button.id == "btn-cancel":
            self.action_quit()
    
    def _collect_values(self) -> dict:
        """Collect all values from all tabs."""
        values = {}
        
        # General tab
        try:
            general = self.query_one(GeneralTab)
            general_values = general.get_values()
            if "appearance" not in values:
                values["appearance"] = {}
            values["appearance"].update(general_values)
            # Extract theme separately
            if "theme" in general_values:
                values["appearance"]["theme"] = general_values["theme"]
        except Exception:
            pass
        
        # Widgets tab
        try:
            widgets = self.query_one(WidgetsTab)
            widgets_values = widgets.get_values()
            values.update(widgets_values)
        except Exception:
            pass
        
        # Spaces tab
        try:
            spaces = self.query_one(SpacesTab)
            spaces_values = spaces.get_values()
            values.update(spaces_values)
        except Exception:
            pass
        
        # Icons tab
        try:
            icons = self.query_one(IconsTab)
            icons_values = icons.get_values()
            values.update(icons_values)
        except Exception:
            pass
        
        # Integrations tab
        try:
            integrations = self.query_one(IntegrationsTab)
            int_values = integrations.get_values()
            # Merge integrations carefully
            if "integrations" in int_values:
                if "integrations" not in values:
                    values["integrations"] = {}
                for k, v in int_values["integrations"].items():
                    if k not in values["integrations"]:
                        values["integrations"][k] = {}
                    values["integrations"][k].update(v)
            if "paths" in int_values:
                values["paths"] = int_values["paths"]
        except Exception:
            pass
        
        # Advanced tab
        try:
            advanced = self.query_one(AdvancedTab)
            adv_values = advanced.get_values()
            if "appearance" in adv_values:
                if "appearance" not in values:
                    values["appearance"] = {}
                values["appearance"].update(adv_values["appearance"])
            if "toggles" in adv_values:
                values["toggles"] = adv_values["toggles"]
        except Exception:
            pass
        
        return values
    
    def _apply_values(self, values: dict) -> None:
        """Apply collected values to config."""
        # Appearance
        if "appearance" in values:
            for key, val in values["appearance"].items():
                if hasattr(self.config.appearance, key):
                    setattr(self.config.appearance, key, val)
        
        # Widgets
        if "widgets" in values:
            for key, val in values["widgets"].items():
                if hasattr(self.config.widgets, key):
                    setattr(self.config.widgets, key, val)
        
        # System info items
        if "system_info_items" in values:
            for key, val in values["system_info_items"].items():
                if hasattr(self.config.system_info_items, key):
                    setattr(self.config.system_info_items, key, val)
        
        # Space icons and modes
        if "space_icons" in values:
            self.config.space_icons = values["space_icons"]
        if "space_modes" in values:
            self.config.space_modes = values["space_modes"]
        
        # Icons
        if "icons" in values:
            for key, val in values["icons"].items():
                if hasattr(self.config.icons, key):
                    setattr(self.config.icons, key, val)
        
        # Integrations
        if "integrations" in values:
            for int_name, int_vals in values["integrations"].items():
                int_config = getattr(self.config.integrations, int_name, None)
                if int_config:
                    for key, val in int_vals.items():
                        if hasattr(int_config, key):
                            setattr(int_config, key, val)
        
        # Paths
        if "paths" in values:
            self.config.paths = values["paths"]
            # Also update local config
            self.local_config.paths.update(values["paths"])
        
        # Toggles
        if "toggles" in values:
            for key, val in values["toggles"].items():
                if hasattr(self.config.toggles, key):
                    setattr(self.config.toggles, key, val)
    
    def action_save(self) -> None:
        """Save configuration."""
        values = self._collect_values()
        self._apply_values(values)
        
        try:
            save_config(self.config)
            save_local_config(self.local_config)
            self.notify("Configuration saved!", severity="information")
            self.dirty = False
        except Exception as e:
            self.notify(f"Error saving: {e}", severity="error")
    
    def action_save_reload(self) -> None:
        """Save configuration and reload sketchybar."""
        self.action_save()
        
        if reload_sketchybar():
            self.notify("SketchyBar reloaded!", severity="information")
        else:
            self.notify(
                "Config saved but could not reload SketchyBar. "
                "Run 'sketchybar --reload' manually.",
                severity="warning"
            )
    
    def action_help(self) -> None:
        """Show help."""
        self.notify(
            "Ctrl+S: Save | Ctrl+R: Save & Reload | Ctrl+Q: Quit",
            severity="information"
        )
    
    def action_quit(self) -> None:
        """Quit the application."""
        self.exit()


def main():
    """Entry point for the barista TUI."""
    import argparse
    
    parser = argparse.ArgumentParser(
        description="Barista - SketchyBar Configuration TUI"
    )
    parser.add_argument(
        "--config", "-c",
        help="Path to config file (default: ~/.config/sketchybar/state.json)"
    )
    parser.add_argument(
        "--version", "-v",
        action="store_true",
        help="Show version and exit"
    )
    
    args = parser.parse_args()
    
    if args.version:
        from . import __version__
        print(f"barista {__version__}")
        return
    
    app = BaristaApp(config_path=args.config)
    app.run()


if __name__ == "__main__":
    main()
