#!/usr/bin/env sh
set -eu

ROOT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
BUILD_DIR="$ROOT_DIR/build"
LUA_SRC_DIR="$ROOT_DIR/lua"
LUA_DST_DIR="$BUILD_DIR/lua"

if [ ! -d "$BUILD_DIR" ]; then
  echo "[ERROR] build directory not found: $BUILD_DIR"
  echo "Please run: cmake -S $ROOT_DIR -B $BUILD_DIR"
  exit 1
fi

if [ ! -f "$BUILD_DIR/Makefile" ]; then
  echo "[INFO] Makefile not found, generating with CMake..."
  cmake -S "$ROOT_DIR" -B "$BUILD_DIR"
fi

echo "[1/2] Building with make..."
if command -v nproc >/dev/null 2>&1; then
  JOBS=$(nproc)
else
  JOBS=4
fi
make -C "$BUILD_DIR" -j"$JOBS"

echo "[2/2] Syncing lua scripts to build directory..."
rm -rf "$LUA_DST_DIR"
cp -r "$LUA_SRC_DIR" "$LUA_DST_DIR"

echo "[DONE] Build and lua sync complete."
