-- ============================================================
-- 端口占用查询核心模块
-- 调用 netstat 命令，解析并返回占用指定端口的进程列表
-- ============================================================
local os_helper    = require("utils.os_helper")
local process_info = require("core.process_info")
local M = {}

--- 查询指定端口的占用情况
-- @param  port   端口号（number 或 string）
-- @return table  结果列表，每项包含：
--                { proto, local_addr, remote_addr, state, pid, process }
function M.query(port)
    local results = {}
    port = tonumber(port)
    if not port then return results end

    local output
    if os_helper.is_windows() then
        -- findstr 用正则匹配 ":端口号" 后跟非数字，避免误匹配 :8080x
        output = os_helper.exec(
            string.format('netstat -ano | findstr /R ":%d[^0-9]"', port))
    else
        output = os_helper.exec(
            string.format("ss -tlnp sport = :%d; netstat -tlnp | grep :%d", port, port))
    end

    if output == "" then return results end

    -- netstat 输出格式（Windows）：
    --   TCP    0.0.0.0:80     0.0.0.0:0    LISTENING    1234
    --   UDP    0.0.0.0:53     *:*                        876
    for line in output:gmatch("[^\r\n]+") do
        local proto, local_addr, remote_addr, state, pid =
            line:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%s*$")

        -- UDP 只有 4 列（无 state），单独匹配
        if not proto then
            proto, local_addr, remote_addr, pid =
                line:match("^%s*(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%s*$")
            if proto then state = "-" end
        end

        if proto then
            -- 确认本地地址包含目标端口
            local lport = local_addr:match(":(%d+)$")
            if lport and tonumber(lport) == port then
                table.insert(results, {
                    proto       = proto,
                    local_addr  = local_addr,
                    remote_addr = remote_addr or "*:*",
                    state       = state or "-",
                    pid         = pid,
                    process     = process_info.get_name(pid),
                })
            end
        end
    end

    return results
end

return M
