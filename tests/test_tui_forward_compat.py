#!/usr/bin/env python3
"""Forward-compatibility regressions for configured TUI select values."""

from __future__ import annotations

import tempfile
import sys
import unittest
from pathlib import Path

from textual.widgets import Select

ROOT = Path(__file__).resolve().parents[1]
if str(ROOT) not in sys.path:
    sys.path.insert(0, str(ROOT))

from tui.app import BaristaApp  # noqa: E402


FUTURE_THEME = "future-theme-v99"
FUTURE_SPACE_MODE = "future-layout-v99"


class TuiForwardCompatibilityTests(unittest.IsolatedAsyncioTestCase):
    async def test_future_select_values_mount_and_noop_save_is_byte_exact(
        self,
    ) -> None:
        with tempfile.TemporaryDirectory() as tempdir:
            state_file = Path(tempdir) / "state.json"
            original = (
                b'{"_version":77,"appearance":{"theme":"future-theme-v99"},'
                b'"space_modes":{"1":"future-layout-v99"},'
                b'"future_state":{"nested":[1,2,3]}}\n'
            )
            state_file.write_bytes(original)
            app = BaristaApp(config_path=str(state_file))

            async with app.run_test(size=(120, 50)) as pilot:
                await pilot.pause()
                theme = app.query_one("#theme", Select)
                space_mode = app.query_one("#space_mode_1", Select)

                self.assertEqual(theme.value, FUTURE_THEME)
                self.assertEqual(space_mode.value, FUTURE_SPACE_MODE)
                self.assertIn(
                    FUTURE_THEME,
                    [value for _, value in theme._options],
                )
                self.assertIn(
                    FUTURE_SPACE_MODE,
                    [value for _, value in space_mode._options],
                )

                self.assertTrue(app.action_save())
                await pilot.pause()

            self.assertEqual(state_file.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
