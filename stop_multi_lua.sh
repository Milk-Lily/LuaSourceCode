#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
EXE="$BUILD_DIR/LuaSourceCode"
REG_DIR="/tmp/milkdebug-${USER:-$(id -un)}"
GROUP="${MILKDEBUG_GROUP:-$(basename "$ROOT_DIR")}"
STATE_FILE="$REG_DIR/$GROUP.pids"
HEARTBEAT_PID_FILE="$REG_DIR/$GROUP.heartbeat.pid"

if [ -f "$HEARTBEAT_PID_FILE" ]; then
  heartbeat_pid=$(cat "$HEARTBEAT_PID_FILE" 2>/dev/null || true)
  if [ -n "$heartbeat_pid" ]; then
    kill "$heartbeat_pid" 2>/dev/null || true
  fi
  rm -f "$HEARTBEAT_PID_FILE"
fi

kill_pid() {
  pid="$1"
  [ -n "$pid" ] || return 0
  if kill -0 "$pid" 2>/dev/null; then
    echo "[multi] stopping pid=$pid"
    kill "$pid" 2>/dev/null || true
  fi
  rm -f "$REG_DIR/$pid.json"
}

if [ -f "$STATE_FILE" ]; then
  while read -r pid port log_file; do
    kill_pid "$pid"
  done < "$STATE_FILE"
  rm -f "$STATE_FILE"
fi

if [ -d "$REG_DIR" ]; then
  for file in "$REG_DIR"/*.json; do
    [ -f "$file" ] || continue
    if grep -q "\"exe\":\"$EXE\"" "$file" 2>/dev/null; then
      pid=$(sed -n 's/.*"pid":[ ]*\([0-9][0-9]*\).*/\1/p' "$file")
      kill_pid "$pid"
      rm -f "$file"
    fi
  done
fi

echo "[multi] stopped $GROUP processes"
