# Copilot Instructions

## Project Overview

C++ executable that embeds the **Lua 5.4 interpreter** (all `l*.c` sources compiled in directly — no external Lua shared library) and runs a Lua application for real-time port/process monitoring. Also serves as a remote debug target for the **MyLuaDebugger IntelliJ plugin** via MobDebug.

## Build

```sh
# Linux/WSL — configure (first time only)
cmake -S . -B build

# Build + sync lua/ scripts to build output
./make_and_copy_lua.sh

# Build, sync, and run
./run.sh

# Build, sync, and run in background-listen debug mode
./listenbg.sh
```

Windows: open `LuaSourceCode.sln` in Visual Studio. The post-build step in `CMakeLists.txt` copies `lua/` into the build output automatically.

> The shell scripts use `build/` as the build directory. CLion defaults to `cmake-build-debug/`. Both are valid — just be consistent.

There are no automated tests. `testlua.lua` (root) and `SkipList.lua`/`Leaderboard.lua` are standalone scripts run manually with the built executable or a system Lua interpreter.

## Execution Flow

```
LuaSourceCode (C++)
  └─> lua/debugger/Entry.lua — sets package.path / package.cpath, loads mobdebug
       └─> require("test")   — infinite tick loop (primary debug target)
       or
       └─> require("main")   — Windows HTA port-monitor GUI
```

`Entry.lua` (now under `lua/debugger/`) detects which module to load. Currently hardcoded to `require("test")` — change to `require("main")` to launch the port monitor GUI. Its own `package.path`/`package.cpath` setup uses the parent of its directory (`lua/`) as the base, so `require("test")`, `require("core.xxx")`, etc. still resolve correctly, while `require("debugger.mobdebug")`, `require("debugger.config")`, `require("debugger.registry")` resolve to sibling files in `lua/debugger/`.

## Key Architecture Points

### C++ ↔ Lua Bridge
`LuaSourceCode.cpp` registers one global Lua function:
- `sleep(seconds)` — implemented with POSIX `select()` so `Ctrl+C` (SIGINT) interrupts it immediately. The signal sets `g_interrupted`, `lua_sleep` calls `luaL_error(L, "interrupted")`, and `main()` suppresses that specific error string.

### MobDebug Remote Debugging
Controlled entirely by environment variables read in `Entry.lua`:

| Variable | Default | Values |
|---|---|---|
| `MOBDEBUG_MODE` | `start` | `start` (connects to IDE), `listenbg` (listens for IDE) |
| `MOBDEBUG_HOST` | `127.0.0.1` | IDE hostname |
| `MOBDEBUG_PORT` | `8172` | TCP port |
| `MOBDEBUG_CHECKCOUNT` | `1` | Hook frequency in `listenbg` mode |
| `MOBDEBUG_EVAL_INLINE` | (unset) | `1` to enable inline eval |

In `listenbg` mode, `Entry.lua` sets `__mobdebug_try_attach` as a global function that `test.lua` calls each tick to poll for a debugger connection.

### Port Monitor — Dual Implementation
There are **two independent implementations** of the port-monitor UI:

1. **`lua/main.lua` + `lua/ui/window.lua`** — Generates a complete HTA (Windows HTML Application) source string, writes it to `%TEMP%\port_monitor_lua.hta`, and launches it via `mshta.exe`. The HTA uses VBScript + JavaScript with async `netstat`/`tasklist` polling. Template variables in `window.lua` use `{{KEY}}` placeholders replaced with `gsub`.

2. **`lua/ui/port_input.lua` + `lua/ui/result_display.lua` + `lua/utils/timer.lua`** — IUP-based native GUI (requires `iuplua`). Currently unused by any entry point.

### Module Layout
`lua/` directory mirrors `package.path`. Always use dot-separated module names matching the directory hierarchy:
- `require("core.port_monitor")` → `lua/core/port_monitor.lua`
- `require("utils.os_helper")` → `lua/utils/os_helper.lua`
- `require("config.settings")` → `lua/config/settings.lua`

## Conventions

- **Always use `utils/os_helper.exec(cmd)`** instead of raw `io.popen`. It appends `2>NUL` (Windows) or `2>/dev/null` (Linux) automatically.
- **Cross-platform detection**: use `os_helper.is_windows()` which checks `package.config:sub(1,1) == "\\"`.
- **`lua/mobdebug.lua` must not be modified** — it is the unmodified MobDebug v0.805 library.
- **All `pcall` around mobdebug calls**: mobdebug integration is always wrapped in `pcall` so a missing/unreachable debugger never crashes the application.
- **Linux CMake flags**: `LUA_USE_LINUX` define, links `-lm -ldl`, uses `-Wl,-E` to export Lua API symbols so `dlopen`'d C modules can resolve them.
- **Modules return a table `M`** (the standard Lua module pattern). The module table is returned at the end of the file.
- **Configuration is centralized** in `lua/config/settings.lua`. UI sizing, refresh interval, and default port all come from there.
