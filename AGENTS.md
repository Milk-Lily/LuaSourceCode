# LuaSourceCode — Agent Instructions

C++ host that embeds the Lua 5.4 interpreter and runs a Lua application for port monitoring. Also serves as the **remote Lua target** for the MyLuaDebugger IntelliJ plugin.

## Build

```bash
# Configure + build (Linux/WSL)
cmake -B cmake-build-debug -S .
cmake --build cmake-build-debug

# Or use the helper scripts
./make_and_copy_lua.sh       # build & copy lua/ to output
./run.sh                     # run the built executable

# Listen for debugger (starts mobdebug listener in background)
./listenbg.sh
```

Windows: open `LuaSourceCode.sln` in Visual Studio or use CMake with the MSVC generator.

Post-build, CMake copies the entire `lua/` directory alongside the executable.

## Execution Flow

```
LuaSourceCode (C++)
  └─> lua/debugger/Entry.lua ← entry point; sets up package.path
       └─> require("test")  ← infinite tick loop (debug target)
       or
       └─> require("main")  ← Windows HTA port-monitor GUI
```

## Key Files

| File | Purpose |
|------|---------|
| `lua/debugger/Entry.lua` | Entry point; configures `package.path`, loads mobdebug |
| `lua/debugger/mobdebug.lua` | Remote debugger library v0.805 (do not modify) |
| `lua/debugger/config.lua` | Debug settings (env var overrides take precedence) |
| `lua/debugger/registry.lua` | Multi-process registry for IDE discovery via SSH |
| `lua/main.lua` | Generates & launches Windows HTA port-monitor GUI via `mshta.exe` |
| `lua/test.lua` | Simple infinite loop — primary mobdebug debug target |
| `lua/config/settings.lua` | App configuration (`refresh_interval`, `default_port`, window size) |
| `lua/core/port_monitor.lua` | `netstat -ano` (Windows) / `ss -tlnp` (Linux) parser |
| `lua/core/process_info.lua` | PID → process name (`tasklist` / `ps`) |
| `lua/ui/` | IUP GUI controls (Windows only) |
| `lua/utils/os_helper.lua` | Cross-platform `is_windows()` and `exec(cmd)` |
| `LuaSourceCode.cpp` | C++ main: embeds Lua, registers `sleep()`, runs `lua/debugger/Entry.lua` |

## Connecting the Debugger

MobDebug connects to a **waiting IDE** (MyLuaDebugger plugin). In `Entry.lua`:

```lua
local ok, mobdebug = pcall(require, "debugger.mobdebug")
if ok then
    mobdebug.start("IDE_HOST", 8172)   -- connects to IDE TCP server
end
```

The IDE plugin (`MobDebugServer`) listens on port **8172** by default and waits for Lua to call `mobdebug.start()`.

## Conventions

- `lua/` directory structure mirrors `package.path` — modules are in subdirectories (`core/`, `ui/`, `utils/`, `config/`).
- `utils/os_helper.exec()` suppresses stderr by appending `2>nul` (Windows) or `2>/dev/null` (Linux); always use it instead of raw `io.popen`.
- The `main.lua` HTA approach is Windows-only (`mshta.exe`). The `port_monitor.lua` / `process_info.lua` backend is cross-platform.
- All Lua C source files (`lapi.c`, `lvm.c`, etc.) are compiled directly into the executable — there is no separate `lua.dll`.

## CMakeLists Notes

- C++14 standard.
- Linux links `-lm` (math) and `-ldl` (dynamic loader).
- The `lua/` folder is copied to the build output directory as a post-build step, so runtime file paths are relative to the executable.
