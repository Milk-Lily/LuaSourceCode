---
--- Created by MilkLily
--- DateTime: 2026/4/2 23:50
---
--- 端口进程实时监控 —— 启动入口
--- 运行方式: lua lua/Entry.lua
---

-- 将 Entry.lua 所在目录加入 package.path，
-- 使得 require("main")、require("core.xxx")、require("ui.xxx") 等均可正常解析。
local _src = debug.getinfo(1, "S").source:sub(2)          -- 去掉前缀 '@'
local _dir = _src:match("(.*[/\\])") or "./"
package.path = _dir .. "?.lua;"
            .. _dir .. "?/init.lua;"
            .. package.path

require("main")
