#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

sh "$ROOT_DIR/make_and_copy_lua.sh"

export MOBDEBUG_MODE=listenbg
export MOBDEBUG_PORT=${MOBDEBUG_PORT:-8172}

exec "$ROOT_DIR/build/LuaSourceCode"
