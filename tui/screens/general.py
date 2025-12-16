"""General settings tab - appearance configuration."""

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, Label, Select, Input, Button
from textual.widget import Widget

from ..config import BaristaConfig, THEMES, parse_color, format_color


class ColorPreview(Static):
    """A small color preview box."""
    
    DEFAULT_CSS = """
    ColorPreview {
        width: 4;
        height: 1;
        border: solid $primary;
    }
    """
    
    def __init__(self, color: str = "0xC021162F", **kwargs):
        super().__init__(**kwargs)
        self.color = color
        self._update_style()
    
    def _update_style(self):
        a, r, g, b = parse_color(self.color)
        # Convert to CSS rgb
        self.styles.background = f"rgb({r},{g},{b})"
    
    def set_color(self, color: str):
        self.color = color
        self._update_style()


class SliderInput(Horizontal):
    """A labeled input for numeric values with range info."""
    
    DEFAULT_CSS = """
    SliderInput {
        height: 3;
        align: left middle;
    }
    
    SliderInput Label {
        width: 20;
        padding: 0 1;
    }
    
    SliderInput Input {
        width: 12;
    }
    
    SliderInput .range-info {
        width: 16;
        padding: 0 1;
        color: $text-muted;
    }
    """
    
    def __init__(
        self,
        label: str,
        value: int | float,
        min_val: int | float,
        max_val: int | float,
        field_id: str,
        **kwargs
    ):
        super().__init__(**kwargs)
        self.label_text = label
        self.value = value
        self.min_val = min_val
        self.max_val = max_val
        self.field_id = field_id
    
    def compose(self) -> ComposeResult:
        yield Label(self.label_text)
        yield Input(
            str(self.value),
            id=self.field_id,
            type="number",
        )
        yield Static(f"({self.min_val}-{self.max_val})", classes="range-info")


class GeneralTab(Vertical):
    """General appearance settings tab."""
    
    DEFAULT_CSS = """
    GeneralTab {
        padding: 1 2;
    }
    
    GeneralTab .section-header {
        text-style: bold;
        padding: 1 0 0 0;
        color: $accent;
    }
    
    GeneralTab .color-row {
        height: 3;
        align: left middle;
    }
    
    GeneralTab .color-row Label {
        width: 20;
        padding: 0 1;
    }
    
    GeneralTab .color-row Input {
        width: 16;
    }
    
    GeneralTab .color-row ColorPreview {
        margin-left: 1;
    }
    
    GeneralTab .theme-row {
        height: 3;
        align: left middle;
    }
    
    GeneralTab .theme-row Label {
        width: 20;
        padding: 0 1;
    }
    
    GeneralTab .theme-row Select {
        width: 24;
    }
    """
    
    def __init__(self, config: BaristaConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
    
    def compose(self) -> ComposeResult:
        appearance = self.config.appearance
        
        yield Static("Bar Appearance", classes="section-header")
        
        yield SliderInput(
            "Bar Height",
            appearance.bar_height,
            20, 50,
            "bar_height"
        )
        
        yield SliderInput(
            "Corner Radius",
            appearance.corner_radius,
            0, 16,
            "corner_radius"
        )
        
        yield SliderInput(
            "Blur Radius",
            appearance.blur_radius,
            0, 80,
            "blur_radius"
        )
        
        yield SliderInput(
            "Widget Scale",
            appearance.widget_scale,
            0.85, 1.25,
            "widget_scale"
        )
        
        yield SliderInput(
            "Widget Corner Radius",
            appearance.widget_corner_radius,
            0, 16,
            "widget_corner_radius"
        )
        
        # Color picker
        with Horizontal(classes="color-row"):
            yield Label("Bar Color")
            yield Input(
                appearance.bar_color,
                id="bar_color",
                placeholder="0xAARRGGBB"
            )
            yield ColorPreview(appearance.bar_color, id="color_preview")
        
        yield Static("Theme", classes="section-header")
        
        with Horizontal(classes="theme-row"):
            yield Label("Theme")
            yield Select(
                [(t, t) for t in THEMES],
                value=appearance.theme,
                id="theme",
            )
    
    def on_input_changed(self, event: Input.Changed) -> None:
        """Handle input changes."""
        if event.input.id == "bar_color":
            # Update color preview
            preview = self.query_one("#color_preview", ColorPreview)
            preview.set_color(event.value)
    
    def get_values(self) -> dict:
        """Get current form values."""
        values = {}
        
        # Numeric inputs
        for field in ["bar_height", "corner_radius", "blur_radius", "widget_scale", "widget_corner_radius"]:
            try:
                inp = self.query_one(f"#{field}", Input)
                val = inp.value
                if field == "widget_scale":
                    values[field] = float(val)
                else:
                    values[field] = int(val)
            except Exception:
                pass
        
        # Color
        try:
            values["bar_color"] = self.query_one("#bar_color", Input).value
        except Exception:
            pass
        
        # Theme
        try:
            select = self.query_one("#theme", Select)
            if select.value:
                values["theme"] = select.value
        except Exception:
            pass
        
        return values
