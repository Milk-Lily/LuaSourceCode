#!/usr/bin/env sh
set -eu

# 启动 N 个业务进程，全部用 mobdebug（listenbg，默认端口从 8172 开始）。
# 端口冲突、注册表写入都由每个进程自己的 Entry.lua/registry.lua 处理，这里只负责
# 拉起进程和记录 pid，方便 stop_multi_lua.sh 停止。

N="${1:-3}"
ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
EXE="$BUILD_DIR/LuaSourceCode"
# 状态文件放在项目目录下（不是 /tmp），只记录 pid/日志路径，供 stop 脚本使用。
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
  while read -r pid log_file; do
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

# 所有进程都用同一个起始端口（MOBDEBUG_PORT，默认 8172）启动即可，Entry.lua 内置的
# 端口扫描（MOBDEBUG_PORT_RANGE，默认 20）会自动跳过已被占用的端口，不需要在这里
# 手动分配端口，也不需要 MOBDEBUG_DISABLE / AGENT_PORT 之类的覆盖。
i=0
while [ "$i" -lt "$N" ]; do
  log_file="$LOG_DIR/process-$i.log"
  (
    cd "$BUILD_DIR"
    nohup "$EXE" > "$log_file" 2>&1 &
    echo "$!"
  ) > "$STATE_DIR/lastpid"
  pid=$(cat "$STATE_DIR/lastpid")
  rm -f "$STATE_DIR/lastpid"
  echo "$pid $log_file" >> "$STATE_FILE"
  echo "[multi] started pid=$pid log=$log_file"
  i=$((i + 1))
done

echo "[multi] $N process(es) started; each publishes its own mobdebug registry entry"
echo "[multi] under <remote_root>/milkdebug-registry/ automatically (see docs)."
echo "[multi] check logs in $LOG_DIR for the actual bound port of each process."
echo "[multi] stop with: ./stop_multi_lua.sh"
