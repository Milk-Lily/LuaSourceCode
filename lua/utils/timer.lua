-- ============================================================
-- IUP 定时器封装
-- 隐藏 iuplua 依赖，提供简洁的定时回调接口
-- ============================================================
local M = {}

--- 新建一个周期定时器
-- @param interval_ms  触发间隔（毫秒）
-- @param callback     每次到期时调用的无参函数
-- @return IUP timer 对象（可通过 .run = "NO" 暂停）
function M.new(interval_ms, callback)
    local iup   = require("iuplua")
    local timer = iup.timer { time = interval_ms }

    function timer:action_cb()
        callback()
    end

    timer.run = "YES"
    return timer
end

return M
