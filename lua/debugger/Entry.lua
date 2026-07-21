---
--- Created by MilkLily
--- DateTime: 2026/4/2 23:50
---
--- 端口进程实时监控 —— 启动入口
--- 运行方式: ./LuaSourceCode  （从构建目录执行）
---

-- Entry.lua 本身放在 lua/debugger/ 下，但 require("test")/require("core.xxx") 等模块
-- 都在 lua/ 下，所以 package.path/cpath 要以 lua/（Entry.lua 的上一级目录）为基准，
-- 而不是 Entry.lua 自己所在的 debugger/ 目录。
local _src = debug.getinfo(1, "S").source:sub(2)   -- 去掉前缀 '@'
local _entry_dir = _src:match("(.*[/\\])") or "./"  -- .../lua/debugger/
local _dir = _entry_dir:match("(.*[/\\])[^/\\]+[/\\]$") or _entry_dir  -- .../lua/
package.path = _dir .. "?.lua;"
            .. _dir .. "?/init.lua;"
            .. "/usr/share/lua/5.4/?.lua;"
            .. "/usr/share/lua/5.4/?/init.lua;"
            .. package.path

package.cpath = _dir .. "?.so;"
             .. "/usr/lib/x86_64-linux-gnu/lua/5.4/?.so;"
             .. "/usr/lib/lua/5.4/?.so;"
             .. "/usr/local/lib/lua/5.4/?.so;"
             .. package.cpath

-- 调试配置：debugger/config.lua 提供默认值，环境变量优先级更高
local ok_debug_cfg, debug_cfg = pcall(require, 'debugger.config')
if not ok_debug_cfg then debug_cfg = {} end

-- 取字符串配置项：环境变量 > 配置文件 > 默认值
local function env_or_cfg(env_name, cfg_value, default)
    local env_val = os.getenv(env_name)
    if env_val ~= nil then return env_val end
    if cfg_value ~= nil then return cfg_value end
    return default
end

-- 取布尔配置项：环境变量 > 配置文件 > 默认值
local function env_or_cfg_bool(env_name, cfg_value, default)
    local env_val = os.getenv(env_name)
    if env_val ~= nil then return env_val == '1' end
    if cfg_value ~= nil then return cfg_value end
    return default
end

-- 取数字配置项：环境变量 > 配置文件 > 默认值
local function env_or_cfg_num(env_name, cfg_value, default)
    local env_val = os.getenv(env_name)
    if env_val ~= nil then return tonumber(env_val) end
    if cfg_value ~= nil then return cfg_value end
    return default
end

-- MilkDebug Agent：自研调试协议，start() 会阻塞，默认禁用，需显式开启
local agent_enable = env_or_cfg_bool('AGENT_ENABLE', debug_cfg.agent_enable, false)
if agent_enable then
    local ok_agent, agent = pcall(require, 'debugger.agent')
    if ok_agent then
        local agent_port = env_or_cfg_num('AGENT_PORT', debug_cfg.agent_port, 8173)
        print(string.format("[agent] starting on port %d (blocking, agent_enable=true) ...", agent_port))
        local ok_start, start_err = pcall(agent.start, agent_port)
        if not ok_start then
            print("[agent] start failed: " .. tostring(start_err))
        end
    else
        print("[agent] require failed: " .. tostring(agent))
    end
end

-- MobDebug：可用 mobdebug_disable/MOBDEBUG_DISABLE 关闭
local mobdebug_disable = env_or_cfg_bool('MOBDEBUG_DISABLE', debug_cfg.mobdebug_disable, false)
if not mobdebug_disable then
    local ok_mob, mobdebug_or_err = pcall(require, 'debugger.mobdebug')
    if ok_mob then
        local _base = _dir:gsub("\\", "/")
        _base = _base:gsub("lua/$", "")
        pcall(mobdebug_or_err.basedir, _base)

        local mobdebug_mode = env_or_cfg('MOBDEBUG_MODE', debug_cfg.mobdebug_mode, 'listenbg')
        local mobdebug_host = env_or_cfg('MOBDEBUG_HOST', debug_cfg.mobdebug_host, '127.0.0.1')
        local mobdebug_port = env_or_cfg_num('MOBDEBUG_PORT', debug_cfg.mobdebug_port, 8172)
        if mobdebug_mode == 'listenbg' then
            -- 非阻塞模式：监听端口，主循环立即继续，IDE 随时可以稍后连接
            _G.__mobdebug_keepalive_on_exit = true
            _G.__mobdebug_report_fullpath = true
            _G.__mobdebug_eval_inline = env_or_cfg_bool('MOBDEBUG_EVAL_INLINE', debug_cfg.mobdebug_eval_inline, false)
            _G.__mobdebug_eval_response_mode = env_or_cfg('MOBDEBUG_EVAL_RESPONSE_MODE', debug_cfg.mobdebug_eval_response_mode, 'inline_value')
            mobdebug_or_err.checkcount = env_or_cfg_num('MOBDEBUG_CHECKCOUNT', debug_cfg.mobdebug_checkcount, 1)

            -- 多进程共用同一起始端口时，端口被占用则自动尝试后面的端口
            local port_range = env_or_cfg_num('MOBDEBUG_PORT_RANGE', debug_cfg.mobdebug_port_range, 20)
            local bound_port, listen_err
            for offset = 0, port_range - 1 do
                local try_port = mobdebug_port + offset
                -- pcall 只表示有没有抛错，bind 是否成功要看第二个返回值
                local ok_call, listen_ok, err = pcall(mobdebug_or_err.listen_background, '*', try_port)
                if ok_call and listen_ok == true then
                    bound_port = try_port
                    break
                end
                listen_err = ok_call and err or listen_ok
            end

            if not bound_port then
                print("[mobdebug] listenbg init skipped: " .. tostring(listen_err))
            else
                print(string.format("[mobdebug] listenbg ready on 0.0.0.0:%d", bound_port))
                print(string.format("[mobdebug] listenbg poll checkcount=%d", mobdebug_or_err.checkcount))

                -- 写 pid/port/心跳到注册表，供 IDE 通过 SSH 发现并连接各个进程
                local ok_registry, registry = pcall(require, 'debugger.registry')
                if ok_registry then
                    local registry_dir_override = env_or_cfg('MOBDEBUG_REGISTRY_DIR', debug_cfg.registry_dir, nil)
                    pcall(registry.publish, bound_port, _base, registry_dir_override)
                else
                    print("[mobdebug] registry unavailable: " .. tostring(registry))
                end

                -- 每个 tick 调用：刷新心跳 + 轮询 IDE 连接，非阻塞
                _G.__mobdebug_try_attach = function()
                    if ok_registry then pcall(registry.heartbeat) end
                    local ok_poll, poll_res = pcall(mobdebug_or_err.poll)
                    if not ok_poll then
                        print("[mobdebug] poll error: " .. tostring(poll_res))
                        return false
                    end
                    return poll_res == true
                end
            end
        else
            -- 旧的阻塞模式：mobdebug.start() 主动连 IDE，最长阻塞 connecttimeout 秒，不推荐使用
            print("[mobdebug] WARNING: MOBDEBUG_MODE=" .. mobdebug_mode ..
                  " is a blocking legacy mode incompatible with MyLuaDebugger; use listenbg instead.")
            _G.__mobdebug_keepalive_on_exit = false
            _G.__mobdebug_report_fullpath = false
            _G.__mobdebug_eval_inline = false
            local ok_debug, debug_err = pcall(mobdebug_or_err.start, mobdebug_host, mobdebug_port)
            if not ok_debug then
                print("[mobdebug] start skipped: " .. tostring(debug_err))
            end
        end
    else
        print("[mobdebug] require failed: " .. tostring(mobdebug_or_err))
    end
end

require("test")

