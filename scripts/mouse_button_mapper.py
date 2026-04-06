#!/usr/bin/env python3

import os
import subprocess
import sys
import time

import Quartz


def _int_env(name: str, default: int) -> int:
    raw = os.environ.get(name)
    if not raw:
        return default
    try:
        return int(raw, 0)
    except ValueError:
        return default


def _log(message: str) -> None:
    now = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[mouse-button-mapper] {now} {message}", flush=True)


MIDDLE_BUTTON = _int_env("BARISTA_MIDDLE_BUTTON", 2)
BACK_BUTTON = _int_env("BARISTA_BACK_BUTTON", 3)
FORWARD_BUTTON = _int_env("BARISTA_FORWARD_BUTTON", 4)

ACTION_BY_BUTTON = {
    MIDDLE_BUTTON: ["/usr/bin/open", "-a", "/System/Applications/Mission Control.app"],
    BACK_BUTTON: ["/opt/homebrew/bin/yabai", "-m", "space", "--focus", "prev"],
    FORWARD_BUTTON: ["/opt/homebrew/bin/yabai", "-m", "space", "--focus", "next"],
}

_event_tap = None


def _run_action(button: int, command: list[str]) -> None:
    try:
        subprocess.Popen(
            command,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        _log(f"button {button} -> {' '.join(command)}")
    except Exception as exc:
        _log(f"FAILED button {button} -> {' '.join(command)}: {exc}")


def _event_callback(proxy, event_type, event, refcon):
    global _event_tap

    if event_type in (
        Quartz.kCGEventTapDisabledByTimeout,
        Quartz.kCGEventTapDisabledByUserInput,
    ):
        if _event_tap is not None:
            Quartz.CGEventTapEnable(_event_tap, True)
            _log("event tap re-enabled after timeout")
        return event

    if event_type not in (Quartz.kCGEventOtherMouseDown, Quartz.kCGEventOtherMouseUp):
        return event

    button = int(Quartz.CGEventGetIntegerValueField(event, Quartz.kCGMouseEventButtonNumber))
    mapped = button in ACTION_BY_BUTTON

    if event_type == Quartz.kCGEventOtherMouseDown:
        command = ACTION_BY_BUTTON.get(button)
        if command:
            _run_action(button, command)
        else:
            _log(f"unmapped button {button} pressed")

    if mapped:
        return None
    return event


def main() -> int:
    global _event_tap

    mask = (
        Quartz.CGEventMaskBit(Quartz.kCGEventOtherMouseDown)
        | Quartz.CGEventMaskBit(Quartz.kCGEventOtherMouseUp)
    )
    _event_tap = Quartz.CGEventTapCreate(
        Quartz.kCGHIDEventTap,
        Quartz.kCGHeadInsertEventTap,
        Quartz.kCGEventTapOptionDefault,
        mask,
        _event_callback,
        None,
    )
    if _event_tap is None:
        _log("FAILED to create event tap (check Input Monitoring/Accessibility for Python)")
        return 1

    source = Quartz.CFMachPortCreateRunLoopSource(None, _event_tap, 0)
    Quartz.CFRunLoopAddSource(
        Quartz.CFRunLoopGetCurrent(), source, Quartz.kCFRunLoopCommonModes
    )
    Quartz.CGEventTapEnable(_event_tap, True)
    _log(
        f"started (middle={MIDDLE_BUTTON} back={BACK_BUTTON} forward={FORWARD_BUTTON})"
    )
    Quartz.CFRunLoopRun()
    return 0


if __name__ == "__main__":
    sys.exit(main())
