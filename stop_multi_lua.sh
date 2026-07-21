#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
STATE_DIR="$ROOT_DIR/milkdebug-multi"
STATE_FILE="$STATE_DIR/pids"
# 默认注册表目录（未在 config.lua 里覆盖 registry_dir 时）；用于清理已停止进程的注册文件。
REG_DIR="$ROOT_DIR/milkdebug-registry"

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

echo "[multi] stopped all tracked processes"
