#!/usr/bin/env sh
set -eu

# 启动 N 个业务进程，全部用 mobdebug（listenbg）。每个进程显式指定不同的起始端口
# （BASE_PORT + 序号），这样脚本自己就知道每个进程用的端口，能打进日志文件名和启动
# 日志里；如果这个端口意外被占用，Entry.lua 内置的端口扫描（MOBDEBUG_PORT_RANGE）
# 还会继续往后找，但正常情况下应该就是 BASE_PORT + 序号。
# 注册表写入由每个进程自己的 registry.lua 处理，这里只负责拉起进程和记录 pid，
# 方便 stop_multi_lua.sh 停止。

N="${1:-3}"
BASE_PORT="${MOBDEBUG_PORT:-8172}"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
EXE="$BUILD_DIR/LuaSourceCode"
# 状态文件放在项目目录下（不是 /tmp），只记录 pid/端口/日志路径，供 stop 脚本使用。
STATE_DIR="$ROOT_DIR/milkdebug-multi"
STATE_FILE="$STATE_DIR/pids"
LOG_DIR="$BUILD_DIR/milkdebug-logs"

if [ "${SKIP_BUILD:-0}" != "1" ]; then
  sh "$ROOT_DIR/make_and_copy_lua.sh"
fi

if [ ! -x "$EXE" ]; then
  echo "[ERROR] executable not found: $EXE"
  echo "Run ./make_and_copy_lua.sh first, or set EXE executable permission."
  exit 1
fi

mkdir -p "$STATE_DIR" "$LOG_DIR"

if [ -f "$STATE_FILE" ]; then
  live_count=0
  while read -r pid port log_file; do
    [ -n "${pid:-}" ] || continue
    if kill -0 "$pid" 2>/dev/null; then
      live_count=$((live_count + 1))
    fi
  done < "$STATE_FILE"
  if [ "$live_count" -gt 0 ]; then
    echo "[ERROR] $live_count process(es) already running."
    echo "Run ./stop_multi_lua.sh first."
    exit 1
  fi
fi

: > "$STATE_FILE"

i=0
while [ "$i" -lt "$N" ]; do
  port=$((BASE_PORT + i))
  log_file="$LOG_DIR/process-$port.log"
  (
    cd "$BUILD_DIR"
    MOBDEBUG_PORT="$port" nohup "$EXE" > "$log_file" 2>&1 &
    echo "$!"
  ) > "$STATE_DIR/lastpid"
  pid=$(cat "$STATE_DIR/lastpid")
  rm -f "$STATE_DIR/lastpid"
  echo "$pid $port $log_file" >> "$STATE_FILE"
  echo "[multi] started pid=$pid port=$port log=$log_file"
  i=$((i + 1))
done

echo "[multi] $N process(es) started; each publishes its own mobdebug registry entry"
echo "[multi] under <remote_root>/milkdebug-registry/ automatically (see docs)."
echo "[multi] stop with: ./stop_multi_lua.sh"
