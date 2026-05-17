-- ============================================================
-- 端口输入栏
-- 文本框 + 查询按钮，支持回车触发
-- ============================================================
local M = {}

--- 创建端口输入控件
-- @param on_query  function(port:number)  用户确认查询时的回调
-- @return container  IUP 容器控件
-- @return text_ctrl  IUP 文本框控件（供外部读取当前值）
function M.new(on_query)
    local iup = require("iuplua")

    local text_ctrl = iup.text {
        value   = "8080",
        size    = "80x",
        tip     = "输入端口号 (1 ~ 65535)",
        expand  = "NO",
    }

    local btn = iup.button {
        title   = "查  询",
        size    = "70x",
        padding = "4x2",
    }

    --- 触发查询
    local function fire()
        local port = tonumber(text_ctrl.value)
        if port and port >= 1 and port <= 65535 then
            on_query(port)
        else
            iup.Message("提示", "请输入合法端口号（1 ~ 65535）")
        end
    end

    -- 按钮点击
    function btn:action()
        fire()
    end

    -- 文本框回车触发
    function text_ctrl:k_any(c)
        if c == iup.K_CR then fire() end
    end

    local container = iup.hbox {
        iup.label { title = "端口号：", alignment = "ACENTER" },
        text_ctrl,
        btn,
        gap       = 6,
        alignment = "ACENTER",
    }

    return container, text_ctrl
end

return M
