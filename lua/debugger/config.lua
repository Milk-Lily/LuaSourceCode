---
--- MobDebug / MilkDebug Agent 配置文件。
---
--- 不想设置环境变量时改这里，改完重启进程生效。同一项如果设置了环境变量，环境变量优先。
---

return {
    -- ── MobDebug ──

    -- 禁用 mobdebug 加载。对应 MOBDEBUG_DISABLE=1。
    mobdebug_disable = false,

    -- "listenbg"（非阻塞，推荐） / "start"（旧的阻塞模式，不要用）。对应 MOBDEBUG_MODE。
    mobdebug_mode = "listenbg",

    -- 仅 mobdebug_mode = "start" 时使用。对应 MOBDEBUG_HOST。
    mobdebug_host = "127.0.0.1",

    -- 监听端口，需和 IDE 侧 Run Configuration 一致。对应 MOBDEBUG_PORT。
    mobdebug_port = 8172,

    -- 端口被占用时向后尝试的端口数量。对应 MOBDEBUG_PORT_RANGE。
    mobdebug_port_range = 20,

    -- 多进程注册表目录，nil 则默认 "<remote_root>/milkdebug-registry"。
    -- 自定义时需和 SSH 面板 Remote Path 保持一致。对应 MOBDEBUG_REGISTRY_DIR。
    registry_dir = nil,

    -- listenbg 模式下每隔多少条 hook 事件轮询一次。对应 MOBDEBUG_CHECKCOUNT。
    mobdebug_checkcount = 1,

    -- 是否启用 Evaluate Expression 内联求值。对应 MOBDEBUG_EVAL_INLINE=1。
    mobdebug_eval_inline = false,

    -- Evaluate Expression 返回值编码方式；IDE 插件当前只按行解析响应，必须用 "inline_value"
    -- 或 "inline_serialized"（值和 "200 OK" 同一行），不要用 "length"（值单独一行发送，插件读不到）。
    -- 对应 MOBDEBUG_EVAL_RESPONSE_MODE。
    mobdebug_eval_response_mode = "inline_value",

    -- ── MilkDebug Agent（自研协议，插件未使用，默认禁用）──

    -- 对应 AGENT_ENABLE=1。
    agent_enable = false,

    -- 对应 AGENT_PORT。
    agent_port = 8173,
}
