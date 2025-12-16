"""Icons tab - icon customization."""

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, Label, Input

from ..config import BaristaConfig


class IconInput(Horizontal):
    """Input for customizing an icon."""
    
    DEFAULT_CSS = """
    IconInput {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    IconInput Label {
        width: 16;
    }
    
    IconInput .icon-preview {
        width: 4;
        text-align: center;
    }
    
    IconInput Input {
        width: 8;
        margin-left: 1;
    }
    
    IconInput .icon-desc {
        color: $text-muted;
        padding-left: 2;
    }
    """
    
    def __init__(self, name: str, icon: str, description: str, icon_id: str, **kwargs):
        super().__init__(**kwargs)
        self.icon_name = name
        self.icon = icon
        self.description = description
        self.icon_id = icon_id
    
    def compose(self) -> ComposeResult:
        yield Label(self.icon_name)
        yield Static(self.icon, classes="icon-preview", id=f"{self.icon_id}_preview")
        yield Input(self.icon, id=self.icon_id, placeholder="icon")
        yield Static(self.description, classes="icon-desc")
    
    def on_input_changed(self, event: Input.Changed) -> None:
        """Update preview when input changes."""
        if event.input.id == self.icon_id:
            preview = self.query_one(f"#{self.icon_id}_preview", Static)
            preview.update(event.value or " ")


class IconsTab(Vertical):
    """Icons customization tab."""
    
    DEFAULT_CSS = """
    IconsTab {
        padding: 1 2;
    }
    
    IconsTab .section-header {
        text-style: bold;
        padding: 1 0;
        color: $accent;
    }
    
    IconsTab .help-text {
        color: $text-muted;
        padding: 0 1 1 1;
    }
    """
    
    ICON_INFO = {
        "apple": ("Apple Menu", "Main menu icon (left)"),
        "quest": ("Quest/Zelda", "Secondary menu icon"),
        "settings": ("Settings", "Settings menu icon"),
        "clock": ("Clock", "Clock widget icon"),
        "calendar": ("Calendar", "Calendar popup icon"),
        "battery": ("Battery", "Battery widget icon"),
        "wifi": ("WiFi", "Network widget icon"),
        "volume": ("Volume", "Volume widget icon"),
    }
    
    def __init__(self, config: BaristaConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
    
    def compose(self) -> ComposeResult:
        yield Static("Icon Customization", classes="section-header")
        yield Static(
            "Customize icons using Nerd Font glyphs. "
            "Copy/paste icons from nerdfonts.com",
            classes="help-text"
        )
        
        icons = self.config.icons
        
        for icon_key, (name, desc) in self.ICON_INFO.items():
            icon_value = getattr(icons, icon_key, "")
            yield IconInput(
                name=name,
                icon=icon_value,
                description=desc,
                icon_id=f"icon_{icon_key}"
            )
    
    def get_values(self) -> dict:
        """Get current icon values."""
        values = {"icons": {}}
        
        for icon_key in self.ICON_INFO.keys():
            try:
                inp = self.query_one(f"#icon_{icon_key}", Input)
                values["icons"][icon_key] = inp.value
            except Exception:
                pass
        
        return values
