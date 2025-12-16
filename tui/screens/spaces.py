"""Spaces tab - space icons and layout modes."""

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal, Grid
from textual.widgets import Static, Label, Input, Select

from ..config import BaristaConfig, SPACE_MODES


class SpaceConfig(Horizontal):
    """Configuration for a single space."""
    
    DEFAULT_CSS = """
    SpaceConfig {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    SpaceConfig Label {
        width: 10;
    }
    
    SpaceConfig .icon-input {
        width: 8;
    }
    
    SpaceConfig Select {
        width: 12;
        margin-left: 2;
    }
    """
    
    def __init__(self, space_num: int, icon: str, mode: str, **kwargs):
        super().__init__(**kwargs)
        self.space_num = space_num
        self.icon = icon
        self.mode = mode
    
    def compose(self) -> ComposeResult:
        yield Label(f"Space {self.space_num}")
        yield Input(
            self.icon,
            id=f"space_icon_{self.space_num}",
            placeholder="icon",
            classes="icon-input"
        )
        yield Select(
            [(m, m) for m in SPACE_MODES],
            value=self.mode,
            id=f"space_mode_{self.space_num}",
        )


class SpacesTab(Vertical):
    """Spaces configuration tab."""
    
    DEFAULT_CSS = """
    SpacesTab {
        padding: 1 2;
    }
    
    SpacesTab .section-header {
        text-style: bold;
        padding: 1 0;
        color: $accent;
    }
    
    SpacesTab .help-text {
        color: $text-muted;
        padding: 0 1 1 1;
    }
    
    SpacesTab .column-headers {
        height: 2;
        padding: 0 1;
    }
    
    SpacesTab .column-headers Label {
        width: 10;
    }
    
    SpacesTab .column-headers .icon-header {
        width: 8;
    }
    
    SpacesTab .column-headers .mode-header {
        width: 12;
        margin-left: 2;
    }
    """
    
    MAX_SPACES = 10
    
    def __init__(self, config: BaristaConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
    
    def compose(self) -> ComposeResult:
        yield Static("Space Configuration", classes="section-header")
        yield Static(
            "Configure icons and layout modes for each space. "
            "Icons support Nerd Font glyphs.",
            classes="help-text"
        )
        
        with Horizontal(classes="column-headers"):
            yield Label("Space")
            yield Label("Icon", classes="icon-header")
            yield Label("Mode", classes="mode-header")
        
        for i in range(1, self.MAX_SPACES + 1):
            icon = self.config.space_icons.get(str(i), "")
            mode = self.config.space_modes.get(str(i), "float")
            yield SpaceConfig(i, icon, mode)
    
    def get_values(self) -> dict:
        """Get current space configuration values."""
        values = {
            "space_icons": {},
            "space_modes": {}
        }
        
        for i in range(1, self.MAX_SPACES + 1):
            # Icon
            try:
                inp = self.query_one(f"#space_icon_{i}", Input)
                if inp.value:
                    values["space_icons"][str(i)] = inp.value
            except Exception:
                pass
            
            # Mode
            try:
                select = self.query_one(f"#space_mode_{i}", Select)
                if select.value:
                    values["space_modes"][str(i)] = select.value
            except Exception:
                pass
        
        return values
