---
--- Created by MilkLily
--- DateTime: 2026/4/2 23:50
---
--- 端口进程实时监控 —— 启动入口
--- 运行方式: ./LuaSourceCode  （从构建目录执行）
---

-- 将 Entry.lua 所在目录加入 package.path，
-- 使得 require("test")、require("core.xxx") 等均可正常解析。
local _src = debug.getinfo(1, "S").source:sub(2)   -- 去掉前缀 '@'
local _dir = _src:match("(.*[/\\])") or "./"
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

-- ── MilkDebug Agent（自研调试协议）──────────────────────────
-- 环境变量：
--   AGENT_MODE=listenbg   启动并阻塞等待 IDE 连接（默认）
--   AGENT_PORT=8173       监听端口
--   AGENT_DISABLE=1       完全禁用
-- ─────────────────────────────────────────────────────────────
local agent_disable = os.getenv('AGENT_DISABLE') == '1'
if not agent_disable then
    local ok_agent, agent = pcall(require, 'debugger.agent')
    if ok_agent then
        local agent_port = tonumber(os.getenv('AGENT_PORT')) or 8173
        print(string.format("[agent] starting on port %d ...", agent_port))
        -- start() 会阻塞等待 IDE 连接并握手，然后安装 hook 返回
        local ok_start, start_err = pcall(agent.start, agent_port)
        if not ok_start then
            print("[agent] start failed: " .. tostring(start_err))
        end
    else
        print("[agent] require failed: " .. tostring(agent))
    end
end

-- ── MobDebug（保留，通过 MOBDEBUG_DISABLE=1 可关闭）─────────
local mobdebug_disable = os.getenv('MOBDEBUG_DISABLE') == '1'
if not mobdebug_disable then
    local ok_mob, mobdebug_or_err = pcall(require, 'mobdebug')
    if ok_mob then
        local _base = _dir:gsub("\\", "/")
        _base = _base:gsub("lua/$", "")
        pcall(mobdebug_or_err.basedir, _base)

        local mobdebug_mode = os.getenv('MOBDEBUG_MODE') or 'start'
        local mobdebug_host = os.getenv('MOBDEBUG_HOST') or '127.0.0.1'
        local mobdebug_port = tonumber(os.getenv('MOBDEBUG_PORT')) or 8172
        if mobdebug_mode == 'listenbg' then
            _G.__mobdebug_keepalive_on_exit = true
            _G.__mobdebug_report_fullpath = true
            _G.__mobdebug_eval_inline = os.getenv('MOBDEBUG_EVAL_INLINE') == '1'
            _G.__mobdebug_eval_response_mode = os.getenv('MOBDEBUG_EVAL_RESPONSE_MODE') or 'length'
            mobdebug_or_err.checkcount = tonumber(os.getenv('MOBDEBUG_CHECKCOUNT')) or 1
            local ok_listen, listen_err = pcall(mobdebug_or_err.listen_background, '*', mobdebug_port)
            if not ok_listen then
                print("[mobdebug] listenbg init skipped: " .. tostring(listen_err))
            else
                print(string.format("[mobdebug] listenbg ready on 0.0.0.0:%d", mobdebug_port))
                print(string.format("[mobdebug] listenbg poll checkcount=%d", mobdebug_or_err.checkcount))
                _G.__mobdebug_try_attach = function()
                    local ok_poll, poll_res = pcall(mobdebug_or_err.poll)
                    if not ok_poll then
                        print("[mobdebug] poll error: " .. tostring(poll_res))
                        return false
                    end
                    return poll_res == true
                end
            end
        else
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

