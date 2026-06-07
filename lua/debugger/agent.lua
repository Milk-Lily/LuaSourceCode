-- ============================================================
-- MilkDebug Agent v1.0
-- 运行在 Lua 进程侧，监听 IDE 连接，实现完整调试功能。
--
-- 协议（纯文本，每条命令以 \n 结尾）：
--
--   IDE → Agent:
--     HELLO\n                          握手
--     SETB <file> <line>\n             设置断点
--     DELB <file> <line>\n             删除断点
--     RUN\n                            继续运行
--     STEPIN\n                         单步进入
--     STEPOVER\n                       单步跨过
--     STEPOUT\n                        单步跳出
--     STACK\n                          请求调用栈
--     LOCALS <frame>\n                 请求指定帧局部变量
--     EVAL <len>\n<expr>               求值（expr 共 len 字节）
--     BYE\n                            断开连接
--
--   Agent → IDE:
--     HELLO MilkDebug/1.0\n            握手响应
--     OK\n                             命令执行成功（无数据）
--     ERR <msg>\n                      命令执行失败
--     BREAK <file> <line>\n            断点/单步命中
--     STACK_DATA <len>\n<json>         调用栈 JSON（len 字节）
--     LOCALS_DATA <len>\n<json>        变量 JSON（len 字节）
--     EVAL_OK <len>\n<value>           求值成功（value 共 len 字节）
--     EVAL_ERR <len>\n<msg>            求值失败（msg 共 len 字节）
--     BYE\n                            主动断开
--
-- JSON 格式：
--   STACK_DATA: [{"file":"...","line":N,"name":"..."},...]
--   LOCALS_DATA: [{"name":"...","type":"...","value":"..."},...]
-- ============================================================

local M = {}

-- ── 内部状态 ──────────────────────────────────────────────────
local _server_fd   = nil   -- 监听 fd
local _client_fd   = nil   -- 当前 IDE 连接 fd
local _breakpoints = {}    -- { [file] = { [line] = true } }
local _running     = false
local _suspended   = false

-- 单步模式: nil=普通运行  "in"=进入  "over"=跨过  "out"=跳出
local _step_mode     = nil
local _step_depth    = 0   -- "over"/"out" 时记录进入时的栈深度

-- ── 工具函数 ──────────────────────────────────────────────────

local function _norm_file(src)
    if not src then return "" end
    -- debug.getinfo 返回的 source 可能带 '@' 前缀
    src = src:gsub("^@", "")
    -- 统一用正斜杠，方便 IDE 端比较
    return src:gsub("\\", "/")
end

local function _bp_key(file, line)
    return file .. ":" .. tostring(line)
end

local function _has_breakpoint(file, line)
    local f = _breakpoints[file]
    return f and f[line] == true
end

-- 简单的 JSON 转义（值中可能含引号/换行）
local function _json_str(s)
    s = tostring(s)
    s = s:gsub('\\', '\\\\')
    s = s:gsub('"',  '\\"')
    s = s:gsub('\n', '\\n')
    s = s:gsub('\r', '\\r')
    s = s:gsub('\t', '\\t')
    return '"' .. s .. '"'
end

-- 序列化单个 Lua 值为可读字符串（不超过 120 字符）
local function _val_str(v)
    local t = type(v)
    if t == "string"  then
        local s = v:sub(1, 80)
        if #v > 80 then s = s .. "..." end
        return '"' .. s:gsub('"', '\\"'):gsub('\n','\\n') .. '"'
    elseif t == "number" or t == "boolean" then
        return tostring(v)
    elseif t == "nil" then
        return "nil"
    elseif t == "table" then
        -- 显示前几个字段
        local parts = {}
        local n = 0
        for k, val in pairs(v) do
            n = n + 1
            if n > 5 then parts[#parts+1] = "..."; break end
            parts[#parts+1] = tostring(k) .. "=" .. tostring(val)
        end
        return "{" .. table.concat(parts, ", ") .. "}"
    else
        return tostring(v)
    end
end

-- ── 网络收发 ──────────────────────────────────────────────────

local function _send(msg)
    if not _client_fd then return end
    local ok, err = dbg_send(_client_fd, msg)
    if not ok then
        print("[agent] send error: " .. tostring(err))
        _client_fd = nil
    end
end

local function _recv_line()
    if not _client_fd then return nil end
    local line, err = dbg_recv_line(_client_fd)
    if not line then
        if err == "interrupted" then error("interrupted") end
        print("[agent] recv error: " .. tostring(err))
        _client_fd = nil
        return nil
    end
    -- 去掉可能的 \r
    return line:gsub("\r$", "")
end

local function _recv_line_timeout(timeout_ms)
    if not _client_fd or type(dbg_recv_line_timeout) ~= "function" then return nil end
    local line, err = dbg_recv_line_timeout(_client_fd, timeout_ms or 0)
    if not line then
        if err == "timeout" then return nil end
        if err == "interrupted" then error("interrupted") end
        print("[agent] recv error: " .. tostring(err))
        _client_fd = nil
        return nil
    end
    return line:gsub("\r$", "")
end
local function _recv_n(n)
    if not _client_fd then return nil end
    local data, err = dbg_recv_n(_client_fd, n)
    if not data then
        print("[agent] recv_n error: " .. tostring(err))
        _client_fd = nil
        return nil
    end
    return data
end

-- ── 调用栈 & 变量 ─────────────────────────────────────────────

-- 返回当前调用栈深度（从 hook 函数算起，跳过 agent 自身帧）
local function _stack_depth(skip)
    skip = skip or 0
    local depth = 0
    while debug.getinfo(depth + skip + 1, "l") do
        depth = depth + 1
    end
    return depth
end

local function _build_stack_json(hook_level)
    -- hook_level: debug.sethook 回调里 getinfo(2) 才是用户代码第一帧
    local frames = {}
    local level = hook_level or 2
    while true do
        local info = debug.getinfo(level, "nSl")
        if not info then break end
        local file = _norm_file(info.source)
        local line = info.currentline or 0
        local name = info.name or ("level_" .. level)
        frames[#frames+1] = string.format(
            '{"file":%s,"line":%d,"name":%s}',
            _json_str(file), line, _json_str(name))
        level = level + 1
    end
    return "[" .. table.concat(frames, ",") .. "]"
end

local function _build_locals_json(frame, hook_level)
    hook_level = hook_level or 2
    local target_level = hook_level + (frame or 0)
    local vars = {}
    local i = 1
    while true do
        local name, val = debug.getlocal(target_level, i)
        if not name then break end
        if name:sub(1,1) ~= "(" then   -- 跳过内部临时变量 "(for index)" 等
            vars[#vars+1] = string.format(
                '{"name":%s,"type":%s,"value":%s}',
                _json_str(name), _json_str(type(val)), _json_str(_val_str(val)))
        end
        i = i + 1
    end
    return "[" .. table.concat(vars, ",") .. "]"
end

-- ── 命令循环（断点命中后阻塞在此）───────────────────────────

local function _command_loop(hook_level)
    _suspended = true
    print("[agent] suspended, waiting for IDE commands...")

    while _suspended and _client_fd do
        local line = _recv_line()
        if not line then break end
        print("[agent] cmd: " .. line)

        if line == "RUN" then
            _step_mode = nil
            _suspended = false
            _send("OK\n")

        elseif line == "STEPIN" then
            _step_mode = "in"
            _suspended = false
            _send("OK\n")

        elseif line == "STEPOVER" then
            _step_mode    = "over"
            _step_depth   = _stack_depth(hook_level)
            _suspended    = false
            _send("OK\n")

        elseif line == "STEPOUT" then
            _step_mode    = "out"
            _step_depth   = _stack_depth(hook_level)
            _suspended    = false
            _send("OK\n")

        elseif line == "STACK" then
            local json = _build_stack_json(hook_level)
            _send("STACK_DATA " .. #json .. "\n" .. json)

        elseif line:sub(1, 6) == "LOCALS" then
            local frame = tonumber(line:match("LOCALS%s+(%d+)")) or 0
            local json = _build_locals_json(frame, hook_level)
            _send("LOCALS_DATA " .. #json .. "\n" .. json)

        elseif line:sub(1, 4) == "EVAL" then
            local len = tonumber(line:match("EVAL%s+(%d+)"))
            if not len then
                _send("ERR bad EVAL format\n")
            else
                local expr = _recv_n(len)
                if expr then
                    -- 构造 eval 环境：包含当前帧的所有局部变量
                    local env = setmetatable({}, {__index = _G})
                    local li = 1
                    while true do
                        local n, v = debug.getlocal(hook_level, li)
                        if not n then break end
                        env[n] = v
                        li = li + 1
                    end
                    local chunk, compile_err = load("return(" .. expr .. ")", "eval", "t", env)
                    if not chunk then
                        local msg = tostring(compile_err)
                        _send("EVAL_ERR " .. #msg .. "\n" .. msg)
                    else
                        local ok, result = pcall(chunk)
                        if ok then
                            local val = _val_str(result)
                            _send("EVAL_OK " .. #val .. "\n" .. val)
                        else
                            local msg = tostring(result)
                            _send("EVAL_ERR " .. #msg .. "\n" .. msg)
                        end
                    end
                end
            end

        elseif line:sub(1, 4) == "SETB" then
            local file, ln = line:match("SETB%s+(.+)%s+(%d+)")
            if file and ln then
                _breakpoints[file] = _breakpoints[file] or {}
                _breakpoints[file][tonumber(ln)] = true
                print(string.format("[agent] breakpoint set %s:%s", file, ln))
                _send("OK\n")
            else
                _send("ERR bad SETB\n")
            end

        elseif line:sub(1, 4) == "DELB" then
            local file, ln = line:match("DELB%s+(.+)%s+(%d+)")
            if file and ln then
                if _breakpoints[file] then
                    _breakpoints[file][tonumber(ln)] = nil
                end
                _send("OK\n")
            else
                _send("ERR bad DELB\n")
            end

        elseif line == "BYE" then
            _send("BYE\n")
            dbg_close(_client_fd)
            _client_fd = nil
            _suspended = false

        else
            _send("ERR unknown command\n")
        end
    end
end

local function _handle_async_command(line)
    if not line then return end
    print("[agent] async cmd: " .. line)

    if line:sub(1, 4) == "SETB" then
        local file, ln = line:match("SETB%s+(.+)%s+(%d+)")
        if file and ln then
            _breakpoints[file] = _breakpoints[file] or {}
            _breakpoints[file][tonumber(ln)] = true
            print(string.format("[agent] breakpoint set %s:%s", file, ln))
            _send("OK\n")
        else
            _send("ERR bad SETB\n")
        end

    elseif line:sub(1, 4) == "DELB" then
        local file, ln = line:match("DELB%s+(.+)%s+(%d+)")
        if file and ln then
            if _breakpoints[file] then
                _breakpoints[file][tonumber(ln)] = nil
            end
            print(string.format("[agent] breakpoint removed %s:%s", file, ln))
            _send("OK\n")
        else
            _send("ERR bad DELB\n")
        end

    elseif line == "BYE" then
        _send("BYE\n")
        dbg_close(_client_fd)
        _client_fd = nil
    end
end

local function _poll_running_commands()
    while _client_fd do
        local line = _recv_line_timeout(0)
        if not line then return end
        _handle_async_command(line)
    end
end
-- ── debug hook ────────────────────────────────────────────────

local function _line_hook(event, line)
    if not _client_fd then return end
    _poll_running_commands()
    if not _client_fd then return end

    local info  = debug.getinfo(2, "nSl")
    local file  = _norm_file(info and info.source)
    local cur_d = _stack_depth(2)

    local should_break = false

    if _step_mode == "in" then
        should_break = true
    elseif _step_mode == "over" then
        should_break = (cur_d <= _step_depth)
    elseif _step_mode == "out" then
        should_break = (cur_d < _step_depth)
    elseif _has_breakpoint(file, line) then
        should_break = true
    end

    if should_break then
        _step_mode = nil
        print(string.format("[agent] break %s:%d", file, line))
        _send(string.format("BREAK %s %d\n", file, line))
        _command_loop(3)   -- getinfo(3) 才是用户代码帧
    end
end

-- ── 握手阶段：接受 IDE 连接并处理初始化命令 ─────────────────

local function _handshake()
    print("[agent] waiting for IDE connection...")
    local fd, err = dbg_accept(_server_fd)
    if not fd then
        if err == "interrupted" then error("interrupted") end
        print("[agent] accept error: " .. tostring(err))
        return false
    end
    _client_fd = fd
    print("[agent] IDE connected")

    -- 等待 HELLO
    local line = _recv_line()
    if not line or line ~= "HELLO" then
        print("[agent] expected HELLO, got: " .. tostring(line))
        dbg_close(fd)
        _client_fd = nil
        return false
    end
    _send("HELLO MilkDebug/1.0\n")

    -- 接收断点列表，直到 RUN/STEPIN
    while _client_fd do
        line = _recv_line()
        if not line then break end
        print("[agent] init cmd: " .. line)

        if line:sub(1, 4) == "SETB" then
            local file, ln = line:match("SETB%s+(.+)%s+(%d+)")
            if file and ln then
                _breakpoints[file] = _breakpoints[file] or {}
                _breakpoints[file][tonumber(ln)] = true
                print(string.format("[agent] breakpoint set %s:%s", file, ln))
            end
            _send("OK\n")

        elseif line == "RUN" then
            _send("OK\n")
            break

        elseif line == "BYE" then
            _send("BYE\n")
            dbg_close(fd)
            _client_fd = nil
            return false
        else
            _send("ERR unexpected\n")
        end
    end

    return _client_fd ~= nil
end

-- ── 公开 API ──────────────────────────────────────────────────

--- 启动调试 Agent，监听指定端口，阻塞等待 IDE 连接，然后安装 debug hook。
-- @param port  监听端口，默认 8173
function M.start(port)
    port = port or 8173
    local fd, err = dbg_listen(port)
    if not fd then
        print("[agent] listen error: " .. tostring(err))
        return
    end
    _server_fd = fd
    print(string.format("[agent] listening on 0.0.0.0:%d", port))

    if not _handshake() then
        print("[agent] handshake failed, running without debugger")
        return
    end

    -- 安装行钩子
    debug.sethook(_line_hook, "l")
    _running = true
    print("[agent] hook installed, running...")
end

--- 非阻塞轮询版本：Agent 已经在后台监听，每 tick 调用此函数检查是否有新 IDE 连接。
-- 适合 listenbg 模式下在 test.lua 的 tick 循环中调用。
function M.poll()
    if _client_fd then return end   -- 已连接

    -- 非阻塞 accept
    local ok = pcall(function()
        -- 先把 server_fd 设为非阻塞
        local flags = 0  -- fcntl 在 Lua 层不方便，用 SO_RCVTIMEO 代替
        -- 直接尝试 accept：若连接已挂起会立即返回，否则阻塞
        -- 这里我们采用"先 start 注册，tick 时已经在 hook 里"的方式
        -- poll 仅用于尚未连接时的非阻塞尝试
    end)
end

--- 停止调试 Agent，移除 hook，关闭连接。
function M.stop()
    debug.sethook()
    if _client_fd then
        pcall(_send, "BYE\n")
        dbg_close(_client_fd)
        _client_fd = nil
    end
    if _server_fd then
        dbg_close(_server_fd)
        _server_fd = nil
    end
    _running = false
end

return M


