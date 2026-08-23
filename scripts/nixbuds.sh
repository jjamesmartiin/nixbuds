#!/usr/bin/env bash
# nixbuds — start, stop and manage the nixbuds daemon and UI.
#
#   nixbuds              show this help
#   nixbuds web          start the core daemon (if needed) and open the web UI
#   nixbuds tui          start the core daemon (if needed) and run the TUI
#   nixbuds start        same as 'web'
#   nixbuds stop         stop the daemon and web UI
#   nixbuds daemon       run the core daemon in the foreground
#   nixbuds --version    print version and exit
#
# `web`, `tui` and `start` stay in the foreground until you quit (Ctrl+C),
# then stop everything they started. `stop` kills whatever is running on
# ports 2020/2021, whether or not this command started it.
#
# Placeholders (@out@, @coreutils@, @procps@, @xdg-utils@) are substituted
# at build time by packages/omarchpods.nix.
set -euo pipefail

export PATH="@coreutils@/bin:@procps@/bin:@xdg-utils@/bin:$PATH"

NIXBUDS="@out@"
CORE="$NIXBUDS/bin/nixbuds-core"
TUI="$NIXBUDS/bin/nixbuds-ui"
WEBUI="$NIXBUDS/bin/nixbuds-webui"

PORT=2020
WEBUI_PORT=2021
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}"
DAEMON_LOG="${NIXBUDS_DAEMON_LOG:-$RUNTIME_DIR/nixbuds-daemon.log}"
DAEMON_PID="$RUNTIME_DIR/nixbuds-daemon.pid"
WEBUI_PID="$RUNTIME_DIR/nixbuds-webui.pid"

usage() {
  cat <<'EOF'
nixbuds — AirPods / Galaxy Buds management (daemon + TUI + web UI)

usage:
  nixbuds web           start the core daemon (if needed) and open the web UI
  nixbuds tui           start the core daemon (if needed) and run the TUI
  nixbuds start         same as 'web'
  nixbuds stop          stop the daemon and web UI
  nixbuds daemon        run the core daemon in the foreground
  nixbuds --version     print version and exit

'web' and 'tui' stay in the foreground until you quit (Ctrl+C), then stop
everything they started. 'stop' stops whatever is running on ports 2020/2021.
EOF
  exit "${1:-0}"
}

port_open() { (exec 3<>"/dev/tcp/127.0.0.1/$1") 2>/dev/null; }

stop_one() {
  local file="$1" pattern="$2" name="$3" pid
  if [ -f "$file" ]; then
    pid="$(cat "$file" 2>/dev/null || true)"
    if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
      kill "$pid" 2>/dev/null || true
      echo "stopped $name (pid $pid)"
      rm -f "$file"
      return 0
    fi
    rm -f "$file"
  fi
  if pgrep -f "$pattern" >/dev/null 2>&1; then
    pkill -f "$pattern" 2>/dev/null || true
    echo "stopped $name"
    return 0
  fi
  return 1
}

stop_all() {
  local stopped=0
  stop_one "$WEBUI_PID" "share/omarchpods/webui" "web UI" && stopped=1
  stop_one "$DAEMON_PID" "bin/nixbuds-core" "daemon" && stopped=1
  if [ "$stopped" = 1 ]; then
    echo "nixbuds stopped"
  else
    echo "nothing running"
  fi
}

CMD="${1:-help}"
case "$CMD" in
  help | -h | --help) usage 0 ;;
  start | web) MODE="web" ;;
  tui) MODE="tui" ;;
  stop) stop_all; exit 0 ;;
  daemon) exec "$CORE" "${@:2}" ;;
  --version | -v | version) exec "$CORE" --version ;;
  *)
    echo "unknown command: $CMD" >&2
    usage 2
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

# --- core daemon -----------------------------------------------------------
if port_open "$PORT"; then
  echo "nixbuds daemon already running (port $PORT)"
else
  echo "starting nixbuds daemon (log: $DAEMON_LOG)"
  "$CORE" >"$DAEMON_LOG" 2>&1 &
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
