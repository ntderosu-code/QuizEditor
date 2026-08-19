#!/usr/bin/env bash
#
# Drives the running app through the gestures that used to destroy the window,
# and fails if the app dies. Covers two crashes that unit tests cannot reach,
# because both were runtime AppKit layout failures rather than bad values:
#
#   #97  Dragging the sidebar divider, or resizing the window, with the AI
#        Suggestions panel open. `.inspector` on the NavigationSplitView looped
#        the constraint pass until the window died.
#   #96  File ▸ New with a shared `.toolbar(id:)`, which made AppKit insert a
#        duplicate sidebar-toggle item.
#
# `DetailLayoutInvariantTests` guards the source-level side of both. This script
# is the runtime side. There is no CI, so run it by hand before a release.
#
# Requirements:
#   - Accessibility permission for the terminal running this
#     (System Settings ▸ Privacy & Security ▸ Accessibility).
#   - Scripts/run-macos-app.sh has been run at least once, so .build has a bundle.
#
# Usage: Scripts/ui-crash-regression.sh
set -uo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP="$ROOT_DIR/.build/QuizEditorApp.app"
DRIVER_SRC="$ROOT_DIR/Scripts/support/uidriver.swift"
DRIVER="$ROOT_DIR/.build/uidriver"

if [[ ! -d "$APP" ]]; then
    echo "No app bundle at $APP. Run Scripts/run-macos-app.sh first." >&2
    exit 1
fi

if [[ ! -x "$DRIVER" || "$DRIVER_SRC" -nt "$DRIVER" ]]; then
    echo "Building the accessibility driver…"
    swiftc -O -o "$DRIVER" "$DRIVER_SRC" || exit 1
fi

alive() {
    osascript -e 'tell application "System Events" to tell process "QuizEditorApp" to get name of window 1' \
        >/dev/null 2>&1 && echo yes || echo no
}
die() { echo "FAIL: crashed while $1"; exit 1; }
key() { osascript -e "tell application \"System Events\" to keystroke $1" >/dev/null 2>&1; }
win() { osascript -e "tell application \"System Events\" to tell process \"QuizEditorApp\" to $1" >/dev/null 2>&1; }

launch() {
    pkill -9 -f QuizEditorApp 2>/dev/null
    sleep 2
    open -n "$APP"
    sleep 6
    # macOS offers to reopen windows after a crash; that dialog is not the
    # document window and would make every check below meaningless.
    osascript -e 'tell application "System Events" to tell process "QuizEditorApp" to click button "Don’t Reopen" of window 1' >/dev/null 2>&1
    sleep 2
    win 'set position of window 1 to {40, 60}'
    win 'set frontmost to true'
    sleep 1
}

exercise() {
    local tag="$1"
    # Every divider in the window, dragged right and then back left.
    for ctr in $("$DRIVER" tree 8 2>/dev/null | grep "AXSplitter" | grep -o 'ctr=[0-9]*,[0-9]*' | cut -d= -f2); do
        local x=${ctr%,*} y=${ctr#*,}
        "$DRIVER" drag "$x" "$y" $((x + 70)) "$y" >/dev/null 2>&1; sleep 0.8
        [[ "$(alive)" == no ]] && die "$tag: dragging a divider right from x=$x"
        "$DRIVER" drag $((x + 70)) "$y" $((x - 50)) "$y" >/dev/null 2>&1; sleep 0.8
        [[ "$(alive)" == no ]] && die "$tag: dragging a divider left from x=$x"
    done
    for w in 1150 980 860 780 1000 1200; do
        win "set size of window 1 to {$w, 700}"
        sleep 0.7
        [[ "$(alive)" == no ]] && die "$tag: resizing the window to ${w}pt"
    done
    for _ in 1 2; do
        key '"a" using {command down, option down}'
        sleep 1
        [[ "$(alive)" == no ]] && die "$tag: toggling the AI panel"
    done
}

launch
[[ "$(alive)" == no ]] && die "launching"

echo "1/4  AI panel open"
exercise "panel open"

echo "2/4  AI panel hidden"
key '"a" using {command down, option down}'; sleep 1
exercise "panel hidden"

echo "3/4  a second document window (#96)"
key '"n" using command down'; sleep 3
[[ "$(alive)" == no ]] && die "File ▸ New"
win 'set position of window 1 to {40, 60}'; sleep 1
exercise "two windows"

echo "4/4  relaunch onto the state all of that saved"
pkill -f QuizEditorApp; sleep 2
open -n "$APP"; sleep 6
[[ "$(alive)" == no ]] && die "relaunching"
exercise "after relaunch"

pkill -f QuizEditorApp 2>/dev/null
echo "PASS: no crash across all four rounds"
