"""Advanced tab - fonts, toggles, and raw JSON editor."""

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, Label, Input, Switch, TextArea, Button

from ..config import BaristaConfig


class FontInput(Horizontal):
    """Input for font configuration."""
    
    DEFAULT_CSS = """
    FontInput {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    FontInput Label {
        width: 16;
    }
    
    FontInput Input {
        width: 30;
    }
    """
    
    def __init__(self, name: str, font: str, font_id: str, **kwargs):
        super().__init__(**kwargs)
        self.font_name = name
        self.font = font
        self.font_id = font_id
    
    def compose(self) -> ComposeResult:
        yield Label(self.font_name)
        yield Input(self.font, id=self.font_id, placeholder="font name")


class AdvancedTab(Vertical):
    """Advanced settings tab."""
    
    DEFAULT_CSS = """
    AdvancedTab {
        padding: 1 2;
    }
    
    AdvancedTab .section-header {
        text-style: bold;
        padding: 1 0;
        color: $accent;
    }
    
    AdvancedTab .help-text {
        color: $text-muted;
        padding: 0 1 1 1;
    }
    
    AdvancedTab .toggle-row {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    AdvancedTab .toggle-row Label {
        width: 20;
    }
    
    AdvancedTab TextArea {
        height: 15;
        margin: 1 0;
    }
    """
    
    def __init__(self, config: BaristaConfig, raw_json: str = "", **kwargs):
        super().__init__(**kwargs)
        self.config = config
        self.raw_json = raw_json
    
    def compose(self) -> ComposeResult:
        appearance = self.config.appearance
        menus = self.config.menus if isinstance(self.config.menus, dict) else {}
        work_menu = menus.get("work", {}) if isinstance(menus, dict) else {}
        work_domain = work_menu.get("workspace_domain", "")
        work_apps_file = work_menu.get("apps_file", "data/work_apps.local.json")
        
        yield Static("Font Configuration", classes="section-header")
        yield Static(
            "Configure fonts used in the status bar. "
            "Requires fonts to be installed on your system.",
            classes="help-text"
        )
        
        yield FontInput("Icon Font", appearance.font_icon, "font_icon")
        yield FontInput("Text Font", appearance.font_text, "font_text")
        yield FontInput("Numbers Font", appearance.font_numbers, "font_numbers")
        yield FontInput("Clock Style", appearance.clock_font_style, "clock_font_style")

        yield Static("Menu Readability", classes="section-header")
        yield FontInput("Menu Font Style", appearance.menu_font_style, "menu_font_style")
        yield FontInput("Header Font Style", appearance.menu_header_font_style, "menu_header_font_style")
        yield FontInput("Font Size Offset", str(appearance.menu_font_size_offset), "menu_font_size_offset")
        yield FontInput("Popup BG Color", appearance.menu_popup_bg_color, "menu_popup_bg_color")
        yield FontInput("Border Color", appearance.popup_border_color, "popup_border_color")

        yield Static("Work Apps Data", classes="section-header")
        yield FontInput("Workspace Domain", str(work_domain), "work_workspace_domain")
        yield FontInput("Apps Data File", str(work_apps_file), "work_apps_file")
        
        yield Static("Feature Toggles", classes="section-header")
        
        with Horizontal(classes="toggle-row"):
            yield Label("Yabai Shortcuts")
            yield Switch(value=self.config.toggles.yabai_shortcuts, id="toggle_yabai_shortcuts")
        
        yield Static("Raw Configuration", classes="section-header")
        yield Static(
            "Edit the raw JSON configuration. "
            "Changes here will override other settings.",
            classes="help-text"
        )
        
        yield TextArea(
            self.raw_json,
            id="raw_json",
            language="json",
        )
    
    def get_values(self) -> dict:
        """Get current advanced settings values."""
        values = {
            "appearance": {},
            "toggles": {},
            "menus": {},
        }
        
        # Fonts
        for font_key in [
            "font_icon",
            "font_text",
            "font_numbers",
            "clock_font_style",
            "menu_font_style",
            "menu_header_font_style",
            "menu_popup_bg_color",
            "popup_border_color",
        ]:
            try:
                inp = self.query_one(f"#{font_key}", Input)
                values["appearance"][font_key] = inp.value
            except Exception:
                pass

        try:
            menu_size_offset = self.query_one("#menu_font_size_offset", Input).value
            values["appearance"]["menu_font_size_offset"] = int(menu_size_offset)
        except Exception:
            pass

        work_menu_updates = {}
        try:
            work_menu_updates["workspace_domain"] = self.query_one("#work_workspace_domain", Input).value
        except Exception:
            pass
        try:
            work_menu_updates["apps_file"] = self.query_one("#work_apps_file", Input).value
        except Exception:
            pass
        if work_menu_updates:
            values["menus"]["work"] = work_menu_updates
        
        # Toggles
        try:
            switch = self.query_one("#toggle_yabai_shortcuts", Switch)
            values["toggles"]["yabai_shortcuts"] = switch.value
        except Exception:
            pass
        
        return values
    
    def get_raw_json(self) -> str:
        """Get the raw JSON text."""
        try:
            textarea = self.query_one("#raw_json", TextArea)
            return textarea.text
        except Exception:
            return ""
