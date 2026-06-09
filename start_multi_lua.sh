#!/usr/bin/env sh
set -eu

N="${1:-3}"
BASE_PORT="${AGENT_PORT:-8173}"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
EXE="$BUILD_DIR/LuaSourceCode"
REG_DIR="/tmp/milkdebug-${USER:-$(id -un)}"
GROUP="${MILKDEBUG_GROUP:-$(basename "$ROOT_DIR")}"
STATE_FILE="$REG_DIR/$GROUP.pids"
HEARTBEAT_PID_FILE="$REG_DIR/$GROUP.heartbeat.pid"
LOG_DIR="$BUILD_DIR/milkdebug-logs"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  sh "$ROOT_DIR/make_and_copy_lua.sh"
fi

if [ ! -x "$EXE" ]; then
  echo "[ERROR] executable not found: $EXE"
  echo "Run ./make_and_copy_lua.sh first, or set EXE executable permission."
  exit 1
fi

mkdir -p "$REG_DIR" "$LOG_DIR"

if [ -f "$STATE_FILE" ]; then
  live_count=0
  while read -r pid port log_file; do
    [ -n "${pid:-}" ] || continue
    if kill -0 "$pid" 2>/dev/null; then
      live_count=$((live_count + 1))
    fi
  done < "$STATE_FILE"
  if [ "$live_count" -gt 0 ]; then
    echo "[ERROR] $live_count $GROUP process(es) already running."
    echo "Run ./stop_multi_lua.sh first."
    exit 1
  fi
fi

if [ -f "$HEARTBEAT_PID_FILE" ]; then
  old_heartbeat=$(cat "$HEARTBEAT_PID_FILE" 2>/dev/null || true)
  if [ -n "$old_heartbeat" ]; then
    kill "$old_heartbeat" 2>/dev/null || true
  fi
  rm -f "$HEARTBEAT_PID_FILE"
fi

: > "$STATE_FILE"

i=0
while [ "$i" -lt "$N" ]; do
  port=$((BASE_PORT + i))
  log_file="$LOG_DIR/process-$port.log"
  (
    cd "$BUILD_DIR"
    AGENT_PORT="$port" AGENT_REMOTE_ROOT="$ROOT_DIR" MOBDEBUG_DISABLE=1 nohup "$EXE" > "$log_file" 2>&1 &
    echo "$!"
  ) > "$REG_DIR/$GROUP.lastpid"
  pid=$(cat "$REG_DIR/$GROUP.lastpid")
  rm -f "$REG_DIR/$GROUP.lastpid"
  echo "$pid $port $log_file" >> "$STATE_FILE"
  echo "[multi] started pid=$pid port=$port log=$log_file"
  i=$((i + 1))
done

(
  json_escape() {
    printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
  }

  exe_json=$(json_escape "$EXE")
  cwd_json=$(json_escape "$BUILD_DIR")
  root_json=$(json_escape "$ROOT_DIR")

  while :; do
    alive=0
    tmp_file="$STATE_FILE.tmp"
    : > "$tmp_file"
    while read -r pid port log_file; do
      [ -n "${pid:-}" ] || continue
      if kill -0 "$pid" 2>/dev/null; then
        alive=$((alive + 1))
        heartbeat=$(date +%s)
        cat > "$REG_DIR/$pid.json" <<EOF
{"pid":$pid,"port":$port,"exe":"$exe_json","cwd":"$cwd_json","remoteRoot":"$root_json","heartbeat":$heartbeat}
EOF
        echo "$pid $port $log_file" >> "$tmp_file"
      else
        rm -f "$REG_DIR/$pid.json"
      fi
    done < "$STATE_FILE"
    mv "$tmp_file" "$STATE_FILE"
    [ "$alive" -gt 0 ] || break
    sleep 5
  done
  rm -f "$HEARTBEAT_PID_FILE"
) &

echo "$!" > "$HEARTBEAT_PID_FILE"
echo "[multi] heartbeat pid=$(cat "$HEARTBEAT_PID_FILE") registry=$REG_DIR"
echo "[multi] stop with: ./stop_multi_lua.sh"
