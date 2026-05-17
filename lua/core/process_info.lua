-- ============================================================
-- 进程信息查询
-- 通过 PID 获取进程名称
-- ============================================================
local os_helper = require("utils.os_helper")
local M = {}

--- 根据 PID 查询进程名称
-- @param  pid  字符串或数字形式的进程 ID
-- @return 进程名称字符串，找不到时返回 "Unknown"
function M.get_name(pid)
    pid = tostring(pid or "")
    if pid == "" or pid == "0" then return "System" end

    local output
    if os_helper.is_windows() then
        -- tasklist /fi "PID eq 1234" /fo csv /nh
        -- 输出示例: "chrome.exe","1234","Console","1","50,000 K"
        output = os_helper.exec(
            string.format('tasklist /fi "PID eq %s" /fo csv /nh', pid))
        local name = output:match('"([^"]+)"')
        return name or "Unknown"
    else
        -- Linux / macOS
        output = os_helper.exec(string.format("ps -p %s -o comm=", pid))
        local name = output:match("^%s*(.-)%s*$")
        return (name and name ~= "") and name or "Unknown"
    end
end

return M
