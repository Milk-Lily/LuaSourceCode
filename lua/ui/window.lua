-- ============================================================
-- HTA（Windows HTML Application）窗口生成器
--
-- 调用链：
--   window.generate_hta(cfg)
--     └─ 返回完整 HTA 源码字符串（由 main.lua 写文件并启动）
--
-- HTA 内部调用链（VBScript + JavaScript 异步协作）：
--   window.onload
--     └─ scheduleQuery()
--         └─ runAsync(cmd, tmpFile, callback)   ← 无黑窗口异步执行
--             ├─ WScript.Shell.Run(..., 0, false)  ← 隐藏窗口，不等待
--             └─ pollFile(tmpFile, callback)        ← 轮询文件就绪
--                 └─ callback(text)
--                     ├─ parseNetstat(text, port) → rows
--                     └─ renderTable(rows, port)
-- ============================================================
---@class window
local M = {}

--- 生成完整 HTA 源码
-- @param  cfg  config/settings.lua 中的配置表
-- @return string  HTA 文件完整内容（调用方负责写盘）
function M.generate_hta(cfg)
    local refresh_ms   = cfg.refresh_interval or 2000
    local default_port = cfg.default_port     or 8080
    local win_w        = cfg.window_width     or 700
    local win_h        = cfg.window_height    or 480
    local refresh_s    = string.format("%.1f", refresh_ms / 1000)

    -- 模板中用 {{KEY}} 作占位符，下方 gsub 统一替换
    local tpl = [==[<!DOCTYPE html>
<html><head>
<meta http-equiv="Content-Type" content="text/html; charset=utf-8"/>
<title>端口进程实时监控器</title>
<hta:application
    applicationname="LuaPortMonitor"
    border="normal"
    caption="yes"
    maximizebutton="yes"
    minimizebutton="yes"
    showintaskbar="yes"
    singleinstance="no"
    sysmenu="yes"
    windowstate="normal"/>
<style>
* { box-sizing: border-box; margin: 0; padding: 0; }
body {
    font-family: "Microsoft YaHei", "Segoe UI", Arial, sans-serif;
    background: #1e1e2e; color: #cdd6f4;
    padding: 14px; font-size: 13px; overflow: hidden;
    user-select: none;
}
h2   { color: #89dceb; margin-bottom: 12px; font-size: 15px; }
.bar { display: flex; align-items: center; gap: 10px; margin-bottom: 10px; flex-wrap: wrap; }
.bar label { color: #a6adc8; }
input[type=text] {
    padding: 5px 9px; border: 1px solid #585b70;
    background: #313244; color: #cdd6f4;
    border-radius: 4px; font-size: 13px; width: 88px;
    user-select: text;
}
button {
    padding: 5px 14px; background: #89b4fa; color: #1e1e2e;
    border: none; border-radius: 4px;
    cursor: pointer; font-size: 13px; font-weight: bold;
}
button:hover { background: #74c7ec; }
button:disabled { background: #45475a; color: #6c7086; cursor: default; }
#result { overflow-y: auto; height: calc(100vh - 112px); }
table   { width: 100%; border-collapse: collapse; font-size: 12px; }
th {
    background: #313244; padding: 7px 10px;
    text-align: left; color: #89dceb;
    border-bottom: 2px solid #45475a; position: sticky; top: 0;
}
td { padding: 6px 10px; border-bottom: 1px solid #2a2a3e; }
tr:hover td { background: #2a2a3e; }
.tcp  { color: #89b4fa; }
.udp  { color: #a6e3a1; }
.empty { color: #f38ba8; padding: 24px; text-align: center; font-size: 13px; }
#status { font-size: 11px; color: #6c7086; margin-top: 6px; }
</style>
</head><body>
<h2>端口 &rarr; 进程 &nbsp; 实时监控</h2>
<div class="bar">
  <label>端口号：</label>
  <input type="text" id="portInput" value="{{DEFAULT_PORT}}" style="user-select:text"
         onkeydown="if(event.keyCode==13){doQuery();}"/>
  <button id="btnQuery" onclick="doQuery()">查 询</button>
  <label style="cursor:pointer">
    <input type="checkbox" id="autoChk" checked onchange="toggleAuto()"/>
    &nbsp;自动刷新（{{REFRESH_S}}s）
  </label>
</div>
<div id="result"><p class="empty">载入中…</p></div>
<div id="status">就绪</div>

<script language="VBScript">
' ── 隐藏窗口执行 cmd，将 stdout+stderr 重定向到 outFile ──────
' 使用 cmd /c 配合重定向，窗口样式=0（隐藏），bWaitOnReturn=False（不阻塞）
Sub RunHidden(cmd, outFile)
    Dim sh
    Set sh = CreateObject("WScript.Shell")
    ' > 覆盖写文件，2>&1 合并 stderr
    sh.Run "cmd /c """ & cmd & """ > """ & outFile & """ 2>&1", 0, False
End Sub

' ── 读取文件全部内容，失败返回空串 ──────────────────────────
Function ReadFile(path)
    Dim fso, f
    ReadFile = ""
    On Error Resume Next
    Set fso = CreateObject("Scripting.FileSystemObject")
    If Not fso.FileExists(path) Then Exit Function
    Set f = fso.OpenTextFile(path, 1, False, -2)  ' -2 = 系统默认编码
    If Err.Number <> 0 Then Exit Function
    ReadFile = f.ReadAll()
    f.Close
End Function

' ── 删除临时文件 ─────────────────────────────────────────────
Sub DeleteFile(path)
    Dim fso
    On Error Resume Next
    Set fso = CreateObject("Scripting.FileSystemObject")
    If fso.FileExists(path) Then fso.DeleteFile path
End Sub
</script>

<script language="JavaScript">
var currentPort = {{DEFAULT_PORT}};
var autoTimer   = null;
var busy        = false;   // 防止查询重入
var tmpBase     = (typeof WScript !== "undefined")
                    ? WScript.CreateObject("Scripting.FileSystemObject")
                           .GetSpecialFolder(2).Path   // 2=Temp
                    : "C:\\Windows\\Temp";

// HTA 中通过 VBScript 获取 %TEMP%
var fso, TEMP_DIR;
try {
    fso      = new ActiveXObject("Scripting.FileSystemObject");
    TEMP_DIR = fso.GetSpecialFolder(2).Path;  // SpecialFolderTemp
} catch (e) {
    TEMP_DIR = "C:\\Windows\\Temp";
}

// ── 异步执行命令：RunHidden → 轮询文件直到出现内容 → callback ──
function runAsync(cmd, suffix, callback) {
    var outFile = TEMP_DIR + "\\pm_lua_" + suffix + ".txt";
    // 先删掉上次残留文件
    try { DeleteFile(outFile); } catch(e) {}
    // 启动（隐藏、不等待）
    RunHidden(cmd, outFile);
    // 轮询，每 80ms 检测文件大小；最多等 8 秒
    var attempts = 0;
    var tid = setInterval(function () {
        attempts++;
        var content = "";
        try { content = ReadFile(outFile); } catch(e) {}
        // 文件存在且有内容（命令已写完），或超时
        if (content.length > 0 || attempts > 100) {
            clearInterval(tid);
            try { DeleteFile(outFile); } catch(e) {}
            callback(content);
        }
    }, 80);
}

// ── 查询入口（用户点击 / 回车）────────────────────────────────
function doQuery() {
    var p = parseInt(document.getElementById("portInput").value, 10);
    if (isNaN(p) || p < 1 || p > 65535) {
        alert("请输入合法端口号（1 ~ 65535）");
        return;
    }
    currentPort = p;
    queryPort(p);
}

// ── 核心查询（异步两步：netstat → tasklist → 渲染）──────────
function queryPort(port) {
    if (busy) return;
    busy = true;
    document.getElementById("status").innerText =
        "正在查询端口 " + port + "…";

    // 第一步：执行 netstat
    runAsync("netstat -ano", "netstat", function (raw) {
        var rows = parseNetstat(raw, port);

        // 第二步：执行 tasklist 获取进程名
        runAsync("tasklist /fo csv /nh", "tasklist", function (tlRaw) {
            var pidMap = parsePidMap(tlRaw);
            renderTable(rows, pidMap, port);
            busy = false;
        });
    });
}

// ── 解析 netstat 输出，返回匹配指定端口的行数组 ─────────────
function parseNetstat(raw, port) {
    var rows  = [];
    var lines = raw.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].replace(/\r/g, "").replace(/^\s+/, "");
        if (line === "") continue;
        var parts = line.split(/\s+/);
        var proto, loc, remote, state, pid;
        if (parts.length >= 5) {
            proto = parts[0]; loc = parts[1]; remote = parts[2];
            state = parts[3]; pid = parts[4];
        } else if (parts.length === 4) {
            proto = parts[0]; loc = parts[1]; remote = parts[2];
            state = "-";      pid = parts[3];
        } else { continue; }
        var m = loc.match(/:(\d+)$/);
        if (!m || parseInt(m[1], 10) !== port) continue;
        rows.push({ proto: proto, loc: loc, remote: remote,
                    state: state, pid: pid });
    }
    return rows;
}

// ── 解析 tasklist /fo csv /nh 输出为 pid→name 映射 ──────────
function parsePidMap(raw) {
    var map   = {};
    var lines = raw.split("\n");
    for (var i = 0; i < lines.length; i++) {
        var m = lines[i].match(/^"([^"]+)","(\d+)"/);
        if (m) map[m[2]] = m[1];
    }
    return map;
}

// ── 渲染结果表格 ──────────────────────────────────────────────
function renderTable(rows, pidMap, port) {
    var result = document.getElementById("result");
    var status = document.getElementById("status");
    var now    = new Date().toLocaleTimeString();
    if (rows.length === 0) {
        result.innerHTML =
            "<p class=\"empty\">端口 " + port + " 未被任何进程占用</p>";
        status.innerText = "端口 " + port + " 未被占用   " + now;
        return;
    }
    var h = "<table><thead><tr>"
          + "<th>协议</th><th>本地地址</th><th>远端地址</th>"
          + "<th>状态</th><th>PID</th><th>进程名</th>"
          + "</tr></thead><tbody>";
    for (var i = 0; i < rows.length; i++) {
        var r   = rows[i];
        var cls = (r.proto.indexOf("TCP") >= 0) ? "tcp" : "udp";
        var pn  = pidMap[r.pid] || "Unknown";
        h += "<tr>"
           + "<td class=\"" + cls + "\">" + r.proto + "</td>"
           + "<td>" + r.loc    + "</td>"
           + "<td>" + r.remote + "</td>"
           + "<td>" + r.state  + "</td>"
           + "<td>" + r.pid    + "</td>"
           + "<td>" + pn       + "</td>"
           + "</tr>";
    }
    h += "</tbody></table>";
    result.innerHTML = h;
    status.innerText = "端口 " + port + "  共 " + rows.length
                     + " 条   最后更新: " + now;
}

// ── 自动刷新开关 ──────────────────────────────────────────────
function toggleAuto() {
    if (document.getElementById("autoChk").checked) {
        autoTimer = setInterval(function () { queryPort(currentPort); },
                                {{REFRESH_MS}});
    } else {
        if (autoTimer) { clearInterval(autoTimer); autoTimer = null; }
    }
}

// ── 页面初始化 ─────────────────────────────────────────────────
window.onload = function () {
    window.resizeTo({{WIDTH}}, {{HEIGHT}});
    queryPort(currentPort);
    autoTimer = setInterval(function () { queryPort(currentPort); },
                            {{REFRESH_MS}});
};
</script>
</body></html>]==]

    -- 替换占位符（均为数字，gsub 安全）
    tpl = tpl:gsub("{{DEFAULT_PORT}}", tostring(default_port))
    tpl = tpl:gsub("{{REFRESH_MS}}",  tostring(refresh_ms))
    tpl = tpl:gsub("{{REFRESH_S}}",   refresh_s)
    tpl = tpl:gsub("{{WIDTH}}",       tostring(win_w))
    tpl = tpl:gsub("{{HEIGHT}}",      tostring(win_h))
    return tpl
end

return M
