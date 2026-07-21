#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

sh "$ROOT_DIR/make_and_copy_lua.sh"

# listenbg 是非阻塞模式：进程立即正常运行，调试器随时可以后来再连接。
# （MOBDEBUG_MODE=listen 不是合法值，会落到阻塞的旧 start 模式，已废弃。）
export MOBDEBUG_MODE=listenbg
export MOBDEBUG_PORT=${MOBDEBUG_PORT:-8172}

exec "$ROOT_DIR/build/LuaSourceCode"
