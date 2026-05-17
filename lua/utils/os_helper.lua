-- ============================================================
-- OS 命令工具
-- 封装 io.popen，统一处理跨平台差异
-- ============================================================
local M = {}

--- 执行系统命令，返回标准输出字符串（失败返回空串）
function M.exec(cmd)
    -- Windows 重定向 stderr 到 NUL，避免弹出错误框
    local redirect = M.is_windows() and " 2>NUL" or " 2>/dev/null"
    local handle = io.popen(cmd .. redirect)
    if not handle then return "" end
    local output = handle:read("*a") or ""
    handle:close()
    return output
end

--- 判断当前操作系统是否为 Windows
function M.is_windows()
    return package.config:sub(1, 1) == "\\"
end

return M
