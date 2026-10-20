#!/bin/sh
# Rebuilds and relaunches the app whenever a source file changes (debug build, no bundling).
# The app restores the screen you were on, so a change is a short blink rather than a restart.
#
#   scripts/dev.sh        watch, rebuild, relaunch
#   Ctrl-C                stop (also quits the app)
set -u
cd "$(dirname "$0")/.."

STAMP="$(mktemp -t arc-dev)"
PID=""

stop_app() {
    if [ -n "$PID" ] && kill -0 "$PID" 2>/dev/null; then
        kill "$PID" 2>/dev/null
        wait "$PID" 2>/dev/null
    fi
    PID=""
}

cleanup() { stop_app; rm -f "$STAMP"; exit 0; }
trap cleanup INT TERM

build_and_run() {
    touch "$STAMP"
    if OUTPUT="$(swift build --product ArcApp 2>&1)"; then
        stop_app
        "$(swift build --product ArcApp --show-bin-path)/ArcApp" &
        PID=$!
        echo "[dev] launched ($(date +%H:%M:%S))"
    else
        echo "$OUTPUT" | grep -E "error:" | head -20
        echo "[dev] build failed; keeping the running app"
    fi
}

changed() {
    find Sources Package.swift -type f \( -name '*.swift' -o -name 'Package.swift' -o -name '*.md' \) -newer "$STAMP" 2>/dev/null | head -1
}

build_and_run
while :; do
    sleep 1
    if [ -n "$(changed)" ]; then
        build_and_run
    fi
done
