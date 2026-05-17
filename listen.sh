#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

# Build and sync lua scripts first.
sh "$ROOT_DIR/make_and_copy_lua.sh"

# Start debugger in listen mode for remote client connection.
export MOBDEBUG_MODE=listen
export MOBDEBUG_PORT=${MOBDEBUG_PORT:-8172}

exec "$ROOT_DIR/build/LuaSourceCode"
