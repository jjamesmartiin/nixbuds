#!/usr/bin/env bash
# nixbuds-start — one command to get nixbuds running.
#
#   nixbuds-start [web|tui]
#
#   web (default)  start the core daemon (if needed), then open the web UI
#                  in your browser (http://127.0.0.1:2021)
#   tui            start the core daemon (if needed), then run the Textual TUI
#
# The script stays in the foreground until you quit (Ctrl+C), then stops
# everything it started. If the daemon is already running (e.g. the NixOS
# user service), it is detected and left alone.
#
# Placeholders (@out@, @coreutils@, @xdg-utils@) are substituted at build
# time by packages/omarchpods.nix.
set -euo pipefail

export PATH="@coreutils@/bin:@xdg-utils@/bin:$PATH"

NIXBUDS="@out@"
DAEMON="$NIXBUDS/bin/nixbuds"
TUI="$NIXBUDS/bin/nixbuds-ui"
WEBUI="$NIXBUDS/bin/nixbuds-webui"

PORT=2020
WEBUI_PORT=2021
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
DAEMON_LOG="${NIXBUDS_DAEMON_LOG:-$RUNTIME_DIR/nixbuds-daemon.log}"
DAEMON_PID="$RUNTIME_DIR/nixbuds-daemon.pid"
WEBUI_PID="$RUNTIME_DIR/nixbuds-webui.pid"

MODE="${1:-web}"
case "$MODE" in
  web | tui) ;;
  *)
    echo "usage: $0 [web|tui]" >&2
    exit 2
    ;;
esac

started_daemon=0
started_webui=0

cleanup() {
  if [ "$started_webui" = 1 ] && [ -f "$WEBUI_PID" ]; then
    kill "$(cat "$WEBUI_PID")" 2>/dev/null || true
    rm -f "$WEBUI_PID"
  fi
  if [ "$started_daemon" = 1 ] && [ -f "$DAEMON_PID" ]; then
    kill "$(cat "$DAEMON_PID")" 2>/dev/null || true
    rm -f "$DAEMON_PID"
  fi
}
trap 'cleanup; exit 130' INT TERM
trap cleanup EXIT

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

# --- core daemon -----------------------------------------------------------
if port_open "$PORT"; then
  echo "nixbuds daemon already running (port $PORT)"
else
  echo "starting nixbuds daemon (log: $DAEMON_LOG)"
  "$DAEMON" >"$DAEMON_LOG" 2>&1 &
  echo $! >"$DAEMON_PID"
  started_daemon=1

  for _ in $(seq 1 100); do
    if port_open "$PORT"; then break; fi
    if ! kill -0 "$(cat "$DAEMON_PID")" 2>/dev/null; then
      echo "daemon exited during startup — see $DAEMON_LOG" >&2
      exit 1
    fi
    sleep 0.2
  done
  if ! port_open "$PORT"; then
    echo "daemon did not open port $PORT in time — see $DAEMON_LOG" >&2
    exit 1
  fi
  echo "daemon ready (port $PORT)"
fi

# --- UI ---------------------------------------------------------------------
if [ "$MODE" = "tui" ]; then
  echo "launching TUI (quit it or press Ctrl+C to stop everything)"
  "$TUI"
  echo "TUI closed — stopping nixbuds"
  exit 0
fi

if port_open "$WEBUI_PORT"; then
  echo "web UI already running at http://127.0.0.1:$WEBUI_PORT"
else
  echo "starting web UI (log: $RUNTIME_DIR/nixbuds-webui.log)"
  "$WEBUI" >"$RUNTIME_DIR/nixbuds-webui.log" 2>&1 &
  echo $! >"$WEBUI_PID"
  started_webui=1

  for _ in $(seq 1 50); do
    if port_open "$WEBUI_PORT"; then break; fi
    sleep 0.1
  done
  if ! port_open "$WEBUI_PORT"; then
    echo "web UI did not start — see $RUNTIME_DIR/nixbuds-webui.log" >&2
    exit 1
  fi
fi

echo "web UI: http://127.0.0.1:$WEBUI_PORT"
command -v xdg-open >/dev/null 2>&1 \
  && xdg-open "http://127.0.0.1:$WEBUI_PORT" >/dev/null 2>&1 || true
echo "press Ctrl+C to stop everything"

while true; do sleep 60; done
