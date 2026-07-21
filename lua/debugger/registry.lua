-- ============================================================
-- MobDebug 多进程注册表
--
-- 每个 listenbg 模式启动的进程，绑定端口成功后把 pid/port/心跳写入
-- <项目根目录>/milkdebug-registry/<pid>.json（项目根目录默认是 Entry.lua 传入的
-- remote_root，也可用 config.lua 的 registry_dir 覆盖）。
--
-- IDE 插件通过 SSH `cat <remotePath>/milkdebug-registry/*.json` 发现所有存活进程。
--
-- 只在 Linux（/proc 可用）下生效，Windows 上所有函数直接空操作。
-- ============================================================
local os_helper = require("utils.os_helper")

local M = {}

local HEARTBEAT_INTERVAL_SECONDS = 5
local REGISTRY_SUBDIR = "milkdebug-registry"

local _pid          = nil
local _exe           = nil
local _cwd           = nil
local _file_path      = nil
local _remote_root    = nil
local _port           = nil
local _last_heartbeat = 0

local function trim(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function detect_identity()
    if _pid ~= nil then return end
    if os_helper.is_windows() then
        _pid, _exe, _cwd = "", "", ""
        return
    end
    _pid = trim(os_helper.exec("readlink /proc/self"))
    _exe = trim(os_helper.exec("readlink -f /proc/self/exe"))
    _cwd = trim(os_helper.exec("readlink -f /proc/self/cwd"))
end

local function json_escape(s)
    s = tostring(s or "")
    s = s:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "")
    return s
end

--- 首次发布，写入注册文件。
--- @param port number             绑定成功的端口
--- @param remote_root string      项目根目录，需和 SSH 面板 Remote Path 一致
--- @param registry_dir_override string|nil 自定义注册表目录，不传则默认 remote_root .. "/milkdebug-registry"
function M.publish(port, remote_root, registry_dir_override)
    if os_helper.is_windows() then return end
    detect_identity()
    if _pid == "" then return end -- 无法识别 pid（非 /proc 环境），放弃注册

    _port        = port
    _remote_root = remote_root or ""

    local dir = registry_dir_override
    if not dir or dir == "" then
        if _remote_root == "" then
            print("[mobdebug] registry skipped: remote_root/registry_dir 均未设置")
            return
        end
        dir = _remote_root:gsub("/+$", "") .. "/" .. REGISTRY_SUBDIR
    end

    os_helper.exec("mkdir -p '" .. dir .. "'")
    _file_path = dir .. "/" .. _pid .. ".json"

    _last_heartbeat = 0 -- 强制下一次 heartbeat() 立即写入
    M.heartbeat()
end

--- 周期性调用，刷新心跳（内部按 HEARTBEAT_INTERVAL_SECONDS 节流，可每个 tick 都调用）。
function M.heartbeat()
    if not _file_path then return end
    local now = os.time()
    if now - _last_heartbeat < HEARTBEAT_INTERVAL_SECONDS then return end
    _last_heartbeat = now

    local json = string.format(
        '{"pid":%s,"port":%d,"exe":"%s","cwd":"%s","remoteRoot":"%s","heartbeat":%d}',
        _pid, _port, json_escape(_exe), json_escape(_cwd), json_escape(_remote_root), now)

    local f = io.open(_file_path, "w")
    if not f then return end
    f:write(json)
    f:close()
end

return M
