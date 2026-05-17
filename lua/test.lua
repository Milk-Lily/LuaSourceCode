---
--- test.lua
--- 每秒输出一次 tick 及当前 os.time()
---

print("[test.lua] loaded, starting tick loop...")

local tick = 0
while true do
    tick = tick + 1
    print(string.format("[tick %d] os.time = %d", tick, os.time()))
    -- os.execute("sleep 1") 依赖 shell，改用纯 Lua 忙等确保跨平台
    -- 但 Lua 标准库没有 sleep；使用 os.clock 做忙等（CPU 占用高）
    -- 推荐方式：os.execute 在 Linux 上可用
    os.execute("sleep 1")
end
