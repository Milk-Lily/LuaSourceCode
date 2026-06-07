#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
LUA_SRC_DIR="$ROOT_DIR/lua"
LUA_DST_DIR="$BUILD_DIR/lua"

if [ ! -d "$BUILD_DIR" ]; then
  echo "[ERROR] build directory not found: $BUILD_DIR"
  echo "Please create/configure build first, for example: cmake -S $ROOT_DIR -B $BUILD_DIR"
  exit 1
fi

if [ ! -d "$LUA_SRC_DIR" ]; then
  echo "[ERROR] lua source directory not found: $LUA_SRC_DIR"
  exit 1
fi

if command -v nproc >/dev/null 2>&1; then
  JOBS=$(nproc)
else
  JOBS=4
fi

echo "[1/2] Building native executable..."
if [ -f "$BUILD_DIR/Makefile" ]; then
  make -C "$BUILD_DIR" -j"$JOBS"
elif [ -f "$BUILD_DIR/build.ninja" ]; then
  cmake --build "$BUILD_DIR" --parallel "$JOBS"
else
  echo "[ERROR] build directory is not configured: $BUILD_DIR"
  echo "Expected Makefile or build.ninja. Run: cmake -S $ROOT_DIR -B $BUILD_DIR"
  exit 1
fi

echo "[2/2] Copying lua scripts to build/lua..."
rm -rf "$LUA_DST_DIR"
cp -r "$LUA_SRC_DIR" "$LUA_DST_DIR"

echo "[DONE] Build complete. Lua scripts synced to: $LUA_DST_DIR"
