#!/bin/bash
# Close the SketchyBar control_center popup (used by the Objective-C panel)

set -euo pipefail

sketchybar --set control_center popup.drawing=off

