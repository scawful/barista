"""Widgets tab - enable/disable widgets."""

from textual.app import ComposeResult
from textual.containers import Vertical, Horizontal
from textual.widgets import Static, Label, Switch

from ..config import BaristaConfig


class WidgetToggle(Horizontal):
    """A toggle for enabling/disabling a widget."""
    
    DEFAULT_CSS = """
    WidgetToggle {
        height: 3;
        align: left middle;
        padding: 0 1;
    }
    
    WidgetToggle Label {
        width: 20;
    }
    
    WidgetToggle Switch {
        width: auto;
    }
    
    WidgetToggle .widget-desc {
        color: $text-muted;
        padding-left: 2;
    }
    """
    
    def __init__(self, name: str, enabled: bool, description: str, widget_id: str, **kwargs):
        super().__init__(**kwargs)
        self.widget_name = name
        self.enabled = enabled
        self.description = description
        self.widget_id = widget_id
    
    def compose(self) -> ComposeResult:
        yield Label(self.widget_name)
        yield Switch(value=self.enabled, id=self.widget_id)
        yield Static(self.description, classes="widget-desc")


class WidgetsTab(Vertical):
    """Widgets enable/disable tab."""
    
    DEFAULT_CSS = """
    WidgetsTab {
        padding: 1 2;
    }
    
    WidgetsTab .section-header {
        text-style: bold;
        padding: 1 0;
        color: $accent;
    }
    """
    
    WIDGET_INFO = {
        "clock": ("Clock", "Time display with calendar popup"),
        "battery": ("Battery", "Battery status with charge level"),
        "volume": ("Volume", "Volume control with popup slider"),
        "network": ("Network", "Network status indicator"),
        "system_info": ("System Info", "CPU, memory, disk usage popup"),
    }
    
    def __init__(self, config: BaristaConfig, **kwargs):
        super().__init__(**kwargs)
        self.config = config
    
    def compose(self) -> ComposeResult:
        yield Static("Status Bar Widgets", classes="section-header")
        
        widgets = self.config.widgets
        
        for widget_key, (name, desc) in self.WIDGET_INFO.items():
            enabled = getattr(widgets, widget_key, True)
            yield WidgetToggle(
                name=name,
                enabled=enabled,
                description=desc,
                widget_id=f"widget_{widget_key}"
            )
        
        yield Static("System Info Items", classes="section-header")
        
        sys_info = self.config.system_info_items
        sys_info_items = {
            "cpu": ("CPU", "CPU usage percentage"),
            "mem": ("Memory", "Memory usage"),
            "disk": ("Disk", "Disk space usage"),
            "net": ("Network", "Network throughput"),
        }
        
        for item_key, (name, desc) in sys_info_items.items():
            enabled = getattr(sys_info, item_key, True)
            yield WidgetToggle(
                name=name,
                enabled=enabled,
                description=desc,
                widget_id=f"sysinfo_{item_key}"
            )
    
    def get_values(self) -> dict:
        """Get current widget toggle values."""
        values = {
            "widgets": {},
            "system_info_items": {}
        }
        
        # Main widgets
        for widget_key in self.WIDGET_INFO.keys():
            try:
                switch = self.query_one(f"#widget_{widget_key}", Switch)
                values["widgets"][widget_key] = switch.value
            except Exception:
                pass
        
        # System info items
        for item_key in ["cpu", "mem", "disk", "net"]:
            try:
                switch = self.query_one(f"#sysinfo_{item_key}", Switch)
                values["system_info_items"][item_key] = switch.value
            except Exception:
                pass
        
        return values
