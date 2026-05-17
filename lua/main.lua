-- ============================================================
-- 主程序入口（零外部 Lua 库依赖）
--
-- 原理：
--   1. 调用 ui/window.lua 生成 HTA（Windows HTML Application）源码
--   2. 将 HTA 写入系统临时目录
--   3. 用 Windows 内置的 mshta.exe 启动该文件 → 弹出真实 GUI 窗口
--
-- HTA 是 Windows 系统自带技术，无需安装任何额外组件。
-- ============================================================
local settings = require("config.settings")
---@type window
local window   = require("ui.window")

-- 1. 生成 HTA 源码
local hta_content = window.generate_hta(settings)

-- 2. 写入系统临时目录
local tmp_dir  = os.getenv("TEMP") or os.getenv("TMP") or "."
local hta_path = tmp_dir .. "\\port_monitor_lua.hta"

local f, err = io.open(hta_path, "w")
if not f then
    io.stderr:write("[错误] 无法创建临时文件: " .. hta_path
                    .. "\n" .. (err or "") .. "\n")
    os.exit(1)
end

-- 写入 UTF-8 BOM，确保 mshta.exe 以 UTF-8 解析文件中的中文
f:write("\xEF\xBB\xBF")
f:write(hta_content)
f:close()

-- 3. 启动 HTA 窗口
--    mshta.exe 是 Windows 内置 HTA 宿主，负责创建窗口并运行其中的脚本
local cmd = string.format('start "" mshta.exe "%s"', hta_path)
os.execute(cmd)

print("端口监控窗口已启动，请查看任务栏。")
print("HTA 文件: " .. hta_path)
