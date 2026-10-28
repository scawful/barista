#!/usr/bin/env python3

import importlib.util
import os
import sys
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "scripts" / "dock_studio.py"


def load_module(music: Path):
    os.environ["BARISTA_MUSIC_DIR"] = str(music)
    spec = importlib.util.spec_from_file_location("dock_studio", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    sys.modules["dock_studio"] = module
    spec.loader.exec_module(module)
    return module


class DockStudioTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.music = Path(self.tmp.name)
        self.studio = load_module(self.music)

    def tearDown(self):
        self.tmp.cleanup()
        os.environ.pop("BARISTA_MUSIC_DIR", None)

    def test_song_pick_is_read_from_the_boxed_output(self):
        text = ("╭──── work on this next ────╮\n│                            │\n"
                "│  ▶ song 01 — untitled   [SPARK]   │\n│    Capture one idea.   │\n")
        self.assertEqual(self.studio.song_line(text), ("song 01 — untitled", "SPARK"))
        self.assertEqual(self.studio.song_line("\x1b[1m▶ demo\x1b[0m"), ("demo", ""))
        self.assertIsNone(self.studio.song_line("nothing to do"))

    def test_logic_projects_are_dated_by_their_project_data(self):
        old = self.music / "Logic/old.logicx"
        new = self.music / "Projects/Logic Projects/Keepers/new.logicx"
        for bundle, stamp in ((old, 2_000), (new, 1_000)):
            data = bundle / "Alternatives/000/ProjectData"
            data.parent.mkdir(parents=True)
            data.write_bytes(b"")
            os.utime(data, (stamp, stamp))
            os.utime(bundle, (stamp, stamp))
        # Saving edits ProjectData without touching the bundle's own date.
        os.utime(new / "Alternatives/000/ProjectData", (3_000, 3_000))
        self.assertEqual([path.name for path, _ in self.studio.logic_projects()], ["new.logicx", "old.logicx"])

    def test_rows_summarise_gear_doctor_song_session_and_now(self):
        devices = {"summary": {"audio_inputs": 6}, "devices": [
            {"display_name": "TR-1000", "connected": True}, {"display_name": "TB-303", "connected": True},
            {"display_name": "JU-06A", "connected": True}, {"display_name": "SH-4D", "connected": False}]}
        doctor = {"status": "warning", "recommended_action": {"label": "Pick your capture input"}}
        now = 100 * 86400
        rows = self.studio.status_rows(devices, doctor, ("song 01", "SPARK"),
                                       [(Path("/m/da funk.logicx"), now - 2 * 86400)], now - 20 * 86400, now)
        self.assertEqual(rows[0], {"title": "Gear · 3 connected", "detail": "TR-1000, TB-303 +1",
                                   "tone": "ok", "action": "Studio Doctor"})
        self.assertEqual(rows[1]["title"], "Pick your capture input")
        self.assertEqual(rows[1]["tone"], "warn")
        self.assertEqual(rows[2], {"title": "Next · song 01", "detail": "SPARK", "tone": "none",
                                   "action": "Next Song"})
        self.assertEqual(rows[3]["title"], "Last session · da funk")
        self.assertEqual(rows[3]["detail"], "2d ago")
        self.assertEqual(rows[4]["tone"], "warn")

    def test_missing_sources_drop_their_rows(self):
        rows = self.studio.status_rows(None, {"status": "ok"}, None, [], None, 0)
        self.assertEqual(rows, [{"title": "Studio ready", "detail": "doctor", "tone": "ok",
                                 "action": "Studio Doctor"}])


if __name__ == "__main__":
    unittest.main()
