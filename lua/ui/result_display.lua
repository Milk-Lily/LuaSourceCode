-- ============================================================
-- 结果显示面板
-- 使用 IUP 多行只读文本框展示端口查询结果
-- ============================================================
local M = {}

--- 创建结果显示控件
-- @return container  IUP 容器控件（放入主窗口布局）
-- @return update_fn  function(results) 用于刷新显示内容
function M.new()
    local iup = require("iuplua")

    -- 表头（固定宽度方便对齐）
    local HEADER = string.format("%-5s  %-26s  %-26s  %-12s  %-8s  %s\n%s",
        "协议", "本地地址", "远端地址", "状态", "PID", "进程名",
        string.rep("-", 100))

    local text_area = iup.text {
        multiline  = "YES",
        expand     = "YES",
        readonly   = "YES",
        font       = "Courier New, 10",
        value      = HEADER .. "\n（等待查询…）",
        scrollbar  = "VERTICAL",
        border     = "YES",
    }

    local container = iup.vbox {
        iup.label { title = "占用详情：" },
        text_area,
        gap = 4,
    }

    --- 更新显示内容
    -- @param results  port_monitor.query() 返回的列表
    local function update(results)
        if #results == 0 then
            text_area.value = HEADER .. "\n（未找到占用该端口的进程）"
            return
        end
        local lines = { HEADER }
        for _, r in ipairs(results) do
            lines[#lines + 1] = string.format(
                "%-5s  %-26s  %-26s  %-12s  %-8s  %s",
                r.proto, r.local_addr, r.remote_addr,
                r.state, r.pid, r.process)
        end
        text_area.value = table.concat(lines, "\n")
    end

    return container, update
end

return M
