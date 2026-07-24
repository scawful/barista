"""Main Barista TUI application."""

from __future__ import annotations

import copy
import json
import shlex
from pathlib import Path

from textual.app import App, ComposeResult
from textual.binding import Binding
from textual.containers import Horizontal, Vertical
from textual.widgets import (
    Header, Footer, Button, Static, TabbedContent, TabPane,
)

from .config import (
    MAX_SAVE_RETRIES,
    STATE_VERSION,
    BaristaConfig,
    ConfigFileError,
    build_config_patch,
    config_write_lock,
    config_write_locks,
    get_state_file,
    load_config,
    load_config_document,
    load_config_document_snapshot,
    load_local_config,
    reload_sketchybar,
    restore_file_snapshot,
    save_config_if_unchanged,
    update_json_array_document,
    validate_config_document,
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
        self.state_file = (
            Path(config_path).expanduser()
            if config_path
            else get_state_file()
        )
        self.local_file = self.state_file.parent / "local.json"
        self.config_path = str(self.state_file)
        self.config: BaristaConfig = load_config(self.state_file)
        self.local_config = load_local_config(self.local_file)
        self.raw_config = load_config_document(self.state_file)
        if not self.raw_config:
            self.raw_config = self.config.model_dump(exclude_none=True)
            self.raw_config.setdefault("_version", STATE_VERSION)
        self._initial_values: dict | None = None
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
                    yield IntegrationsTab(self.config, self.local_config)
                
                with TabPane("Advanced", id="tab-advanced"):
                    raw_json = json.dumps(
                        self.raw_config,
                        indent=2
                    )
                    yield AdvancedTab(self.config, raw_json)
            
            with Horizontal(id="button-bar"):
                yield Button("Save", id="btn-save", variant="primary")
                yield Button("Save & Reload", id="btn-save-reload", variant="success")
                yield Button("Cancel", id="btn-cancel", variant="default")
            
            yield Static(f"Config: {self.state_file}", id="status-bar")
        
        yield Footer()

    def on_mount(self) -> None:
        """Capture the rendered form baseline for change-only persistence."""
        self._initial_values = copy.deepcopy(self._collect_values())
    
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
        values = {
            "appearance": self.query_one(GeneralTab).get_values(),
        }
        values.update(self.query_one(WidgetsTab).get_values())
        values.update(self.query_one(SpacesTab).get_values())
        values.update(self.query_one(IconsTab).get_values())

        integration_values = self.query_one(IntegrationsTab).get_values()
        values["integrations"] = integration_values["integrations"]
        values["paths"] = integration_values["paths"]

        advanced_values = self.query_one(AdvancedTab).get_values()
        values["appearance"].update(advanced_values["appearance"])
        values["toggles"] = advanced_values["toggles"]
        values["menus"] = advanced_values["menus"]
        return values
    
    def _apply_values(
        self,
        values: dict,
        config: BaristaConfig | None = None,
    ) -> None:
        """Apply collected values to config."""
        target = config or self.config

        # Appearance
        if "appearance" in values:
            for key, val in values["appearance"].items():
                if hasattr(target.appearance, key):
                    setattr(target.appearance, key, val)
        
        # Widgets
        if "widgets" in values:
            for key, val in values["widgets"].items():
                if hasattr(target.widgets, key):
                    setattr(target.widgets, key, val)
        
        # System info items
        if "system_info_items" in values:
            for key, val in values["system_info_items"].items():
                if hasattr(target.system_info_items, key):
                    setattr(target.system_info_items, key, val)
        
        # Space icons and modes
        if "space_icons" in values:
            target.space_icons = values["space_icons"]
        if "space_modes" in values:
            target.space_modes = values["space_modes"]
        
        # Icons
        if "icons" in values:
            for key, val in values["icons"].items():
                if hasattr(target.icons, key):
                    setattr(target.icons, key, val)
        
        # Integrations
        if "integrations" in values:
            for int_name, int_vals in values["integrations"].items():
                int_config = getattr(target.integrations, int_name, None)
                if int_config:
                    for key, val in int_vals.items():
                        if hasattr(int_config, key):
                            setattr(int_config, key, val)
        
        # Paths
        if "paths" in values:
            target.paths = values["paths"]
        
        # Toggles
        if "toggles" in values:
            for key, val in values["toggles"].items():
                if hasattr(target.toggles, key):
                    setattr(target.toggles, key, val)

        # Menus (work apps path/domain, etc.)
        if "menus" in values and isinstance(values["menus"], dict):
            existing_menus = target.menus if isinstance(target.menus, dict) else {}
            for menu_key, menu_vals in values["menus"].items():
                if not isinstance(menu_vals, dict):
                    continue
                current = existing_menus.get(menu_key, {})
                if not isinstance(current, dict):
                    current = {}
                current.update(menu_vals)
                existing_menus[menu_key] = current
            target.menus = existing_menus

    def _prepare_work_apps_data(
        self,
        work_menu: dict[str, object],
    ) -> tuple[Path | None, list[dict[str, object]]]:
        """Resolve the effective target and build the managed Google rows."""
        apps_file = str(work_menu.get("apps_file", "") or "").strip()
        workspace_domain = str(work_menu.get("workspace_domain", "") or "").strip()

        def google_url(host: str) -> str:
            if workspace_domain:
                return f"https://{host}/a/{workspace_domain}/"
            return f"https://{host}/"

        apps = [
            {
                "id": "work_google_gmail",
                "label": "Gmail",
                "icon": "󰇮",
                "url": google_url("mail.google.com"),
                "section": "work",
                "order": 1,
                "enabled": True,
            },
            {
                "id": "work_google_calendar",
                "label": "Calendar",
                "icon": "󰃭",
                "url": google_url("calendar.google.com"),
                "section": "work",
                "order": 2,
                "enabled": True,
            },
            {
                "id": "work_google_drive",
                "label": "Drive",
                "icon": "󰉋",
                "url": google_url("drive.google.com"),
                "section": "work",
                "order": 3,
                "enabled": True,
            },
            {
                "id": "work_google_docs",
                "label": "Docs",
                "icon": "󰈬",
                "url": "https://docs.google.com/document/u/0/",
                "section": "work",
                "order": 4,
                "enabled": True,
            },
            {
                "id": "work_google_sheets",
                "label": "Sheets",
                "icon": "󰈛",
                "url": "https://docs.google.com/spreadsheets/u/0/",
                "section": "work",
                "order": 5,
                "enabled": True,
            },
            {
                "id": "work_google_meet",
                "label": "Meet",
                "icon": "󰤙",
                "url": "https://meet.google.com/",
                "section": "work",
                "order": 6,
                "enabled": True,
            },
        ]

        apps_path = None
        if apps_file:
            apps_path = Path(apps_file).expanduser()
            if not apps_path.is_absolute():
                apps_path = self.state_file.parent / apps_path
            apps_path = apps_path.resolve(strict=False)
            if apps_path == self.state_file.resolve(strict=False):
                raise ConfigFileError(
                    "Work Apps Data File must not be the active state file"
                )
        return apps_path, apps

    @staticmethod
    def _work_menu_patch(updates: dict) -> dict[str, object] | None:
        menu_updates = updates.get("menus")
        if not isinstance(menu_updates, dict):
            return None
        work_updates = menu_updates.get("work")
        if not isinstance(work_updates, dict) or not work_updates:
            return None
        return copy.deepcopy(work_updates)

    @staticmethod
    def _effective_work_menu(
        document: dict[str, object],
        candidate: BaristaConfig,
        work_patch: dict[str, object],
    ) -> dict[str, object]:
        candidate_menus = (
            candidate.menus if isinstance(candidate.menus, dict) else {}
        )
        candidate_work = candidate_menus.get("work")
        effective = (
            copy.deepcopy(candidate_work)
            if isinstance(candidate_work, dict)
            else {}
        )
        menus = document.get("menus")
        latest_work = menus.get("work") if isinstance(menus, dict) else None
        if isinstance(latest_work, dict):
            effective.update(copy.deepcopy(latest_work))
        effective.update(copy.deepcopy(work_patch))
        return effective

    @staticmethod
    def _merge_managed_work_apps(
        existing: list[object],
        generated: list[dict[str, object]],
    ) -> list[object]:
        """Replace Barista-managed Google rows while retaining custom rows."""
        custom = [
            row
            for row in existing
            if not (
                isinstance(row, dict)
                and str(row.get("id", "")).startswith("work_google_")
            )
        ]
        return custom + generated

    @staticmethod
    def _apply_work_apps_data(
        updates: dict,
        latest_document: dict[str, object],
        apps: list[object],
    ) -> None:
        """Patch fallback rows while preserving current Apple menu metadata."""
        menu_updates = updates.setdefault("menus", {})
        work_updates = menu_updates.setdefault("work", {})
        work_updates["google_apps"] = apps

        menus = latest_document.get("menus")
        apple = menus.get("apple") if isinstance(menus, dict) else None
        apple = apple if isinstance(apple, dict) else {}
        apple_updates: dict[str, object] = {}

        custom = apple.get("custom")
        if isinstance(custom, list):
            filtered_custom = [
                row
                for row in custom
                if not (
                    isinstance(row, dict)
                    and str(row.get("id", "")).startswith("work_google_")
                )
            ]
            if filtered_custom != custom:
                apple_updates["custom"] = filtered_custom

        sections = apple.get("sections")
        if not isinstance(sections, dict) or "work" not in sections:
            apple_updates["sections"] = {
                "work": {"label": "Work Apps", "order": 3}
            }
        if apple_updates:
            menu_updates["apple"] = apple_updates

    @staticmethod
    def _state_work_apps(work_menu: dict[str, object]) -> list[object]:
        """Return the runtime fallback rows when no nonempty file overrides them."""
        apps = work_menu.get("google_apps")
        return apps if isinstance(apps, list) else []

    @staticmethod
    def _restore_work_apps_or_raise(
        apps_path: Path,
        previous_content: bytes | None,
        written_token: str,
        error: Exception | None = None,
    ) -> None:
        if restore_file_snapshot(
            apps_path,
            previous_content,
            expected_token=written_token,
            acquire_lock=False,
        ):
            return
        detail = f"{error}; " if error is not None else ""
        raise ConfigFileError(
            f"{detail}could not roll back {apps_path} because it changed again"
        ) from error

    def _save_work_apps_transaction(
        self,
        candidate: BaristaConfig,
        updates: dict,
        work_patch: dict[str, object],
    ) -> BaristaConfig:
        """Commit state and derived Work Apps from one current state snapshot."""
        for _ in range(MAX_SAVE_RETRIES):
            preflight_document = load_config_document(self.state_file)
            preflight_work = self._effective_work_menu(
                preflight_document,
                candidate,
                work_patch,
            )
            anticipated_path, _ = self._prepare_work_apps_data(preflight_work)
            lock_paths = [self.state_file]
            if anticipated_path is not None:
                lock_paths.append(anticipated_path)

            with config_write_locks(lock_paths):
                latest_document, state_token = load_config_document_snapshot(
                    self.state_file
                )
                validate_config_document(
                    latest_document,
                    self.state_file,
                )
                effective_work = self._effective_work_menu(
                    latest_document,
                    candidate,
                    work_patch,
                )
                apps_path, generated_apps = self._prepare_work_apps_data(
                    effective_work
                )
                if apps_path != anticipated_path:
                    continue

                fallback_apps = copy.deepcopy(
                    self._state_work_apps(effective_work)
                )
                transaction_updates = copy.deepcopy(updates)
                previous_content: bytes | None = None
                written_token: str | None = None

                if apps_path is None:
                    merged_apps = self._merge_managed_work_apps(
                        fallback_apps,
                        generated_apps,
                    )
                else:
                    previous_content, merged_apps, written_token = (
                        update_json_array_document(
                            apps_path,
                            lambda file_apps: self._merge_managed_work_apps(
                                file_apps if file_apps else fallback_apps,
                                generated_apps,
                            ),
                            acquire_lock=False,
                        )
                    )

                self._apply_work_apps_data(
                    transaction_updates,
                    latest_document,
                    merged_apps,
                )
                try:
                    committed = save_config_if_unchanged(
                        candidate,
                        updates=transaction_updates,
                        state_file=self.state_file,
                        expected_token=state_token,
                        acquire_lock=False,
                    )
                except Exception as save_error:
                    if apps_path is not None and written_token is not None:
                        self._restore_work_apps_or_raise(
                            apps_path,
                            previous_content,
                            written_token,
                            save_error,
                        )
                    raise

                if not committed:
                    if apps_path is not None and written_token is not None:
                        self._restore_work_apps_or_raise(
                            apps_path,
                            previous_content,
                            written_token,
                        )
                    continue
                return load_config(self.state_file)

        raise ConfigFileError(
            f"Could not save {self.state_file}: state changed repeatedly"
        )
    
    def action_save(self) -> bool:
        """Save configuration."""
        try:
            values = self._collect_values()
            updates = (
                build_config_patch(self._initial_values, values)
                if self._initial_values is not None
                else values
            )
            candidate = self.config.model_copy(deep=True)
            self._apply_values(values, candidate)
            candidate = BaristaConfig.model_validate(
                candidate.model_dump(exclude_none=True)
            )
            work_patch = self._work_menu_patch(updates)
            if work_patch is None:
                with config_write_lock(self.state_file):
                    for _ in range(MAX_SAVE_RETRIES):
                        latest_document, state_token = (
                            load_config_document_snapshot(self.state_file)
                        )
                        validate_config_document(
                            latest_document,
                            self.state_file,
                        )
                        if save_config_if_unchanged(
                            candidate,
                            updates=updates,
                            state_file=self.state_file,
                            expected_token=state_token,
                            acquire_lock=False,
                        ):
                            saved_config = load_config(self.state_file)
                            break
                    else:
                        raise ConfigFileError(
                            f"Could not save {self.state_file}: "
                            "state changed repeatedly"
                        )
            else:
                saved_config = self._save_work_apps_transaction(
                    candidate,
                    updates,
                    work_patch,
                )
            self.config = saved_config
            self.notify("Configuration saved!", severity="information")
            self._initial_values = copy.deepcopy(values)
            self.dirty = False
            return True
        except Exception as e:
            self.notify(f"Error saving: {e}", severity="error")
            return False
    
    def action_save_reload(self) -> None:
        """Save configuration and reload sketchybar."""
        if not self.action_save():
            return

        if self.state_file.name != "state.json":
            self.notify(
                "Configuration saved; reload skipped because SketchyBar reads "
                f"{self.state_file.parent}/state.json, not {self.state_file.name}.",
                severity="warning",
            )
            return
        
        if reload_sketchybar(self.state_file.parent):
            self.notify("SketchyBar reloaded!", severity="information")
        else:
            directory = self.state_file.parent.resolve(strict=False)
            helper = directory / "plugins" / "reload_sketchybar.sh"
            manual_command = (
                f"env CONFIG_DIR={shlex.quote(str(directory))} "
                f"BARISTA_CONFIG_DIR={shlex.quote(str(directory))} "
                f"{shlex.quote(str(helper))}"
            )
            self.notify(
                "Config saved but could not reload SketchyBar. "
                f"Run `{manual_command}` manually.",
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
    
    try:
        app = BaristaApp(config_path=args.config)
    except ConfigFileError as exc:
        parser.error(str(exc))
    app.run()


if __name__ == "__main__":
    main()
