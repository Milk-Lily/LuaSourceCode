-- ---
-- --- test.lua
-- --- 每秒输出一次 tick 及当前 os.time()
-- ---
-- 
-- print("[test.lua] loaded, starting tick loop...")
-- 
-- local tick = 0
-- while true do
--     if type(__mobdebug_try_attach) == "function" then
--         __mobdebug_try_attach()
--     end
-- 
--     tick = tick + 1
--     print(string.format("[tick %d] os.time = %d", tick, os.time()))
--     sleep(1)   -- C++ 注册的 sleep，SIGINT 可立即中断
-- end


---
--- test.lua
--- 每秒输出一次 tick 及当前 os.time()
---

print("[test.lua] loaded, starting tick loop...")

local agent_port = os.getenv("AGENT_PORT") or "unknown"
local log_path = os.getenv("MILKDEBUG_TICK_LOG") or "log.log"

local function append_tick_log(message)
    local file, err = io.open(log_path, "a")
    if not file then
        print(string.format("[port %s] failed to open %s: %s", agent_port, log_path, tostring(err)))
        return
    end
    file:write(string.format("[port %s] %s\n", agent_port, message))
    file:close()
end

local tick = 0
while true do
    if type(__mobdebug_try_attach) == "function" then
        __mobdebug_try_attach()
    end

    tick = tick + 1
    local message = string.format("[tick %d] os.time = %d", tick, os.time())
    print(message)
    append_tick_log(message)
    sleep(1)
end