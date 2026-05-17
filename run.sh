#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)

sh "$ROOT_DIR/make_and_copy_lua.sh"

exec "$ROOT_DIR/build/LuaSourceCode"
