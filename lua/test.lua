---
--- test.lua
--- 每秒输出一次 tick 及当前 os.time()
---

print("[test.lua] loaded, starting tick loop...")

local tick = 0
while true do
    if type(__mobdebug_try_attach) == "function" then
        __mobdebug_try_attach()
    end

    tick = tick + 1
    print(string.format("[tick %d] os.time = %d", tick, os.time()))
    sleep(1)   -- C++ 注册的 sleep，SIGINT 可立即中断
end
