// LuaSourceCode.cpp : C++ 嵌入 Lua 源码工程入口（Linux）
//

#include <iostream>
#include <cstdlib>
#include <csignal>
#include <cstring>
#include <sys/select.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <arpa/inet.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

// 信号安全的中断标志
static volatile sig_atomic_t g_interrupted = 0;

static void sigint_handler(int)
{
    g_interrupted = 1;
}

// 注册到 Lua 的 sleep(seconds)：select 会被 SIGINT 立即中断
static int lua_sleep(lua_State* L)
{
    double seconds = luaL_checknumber(L, 1);
    struct timeval tv;
    tv.tv_sec  = (long)seconds;
    tv.tv_usec = (long)((seconds - tv.tv_sec) * 1e6);
    select(0, nullptr, nullptr, nullptr, &tv);
    // select 被信号中断后检查标志，直接从 C 层抛 Lua 错误
    if (g_interrupted) {
        g_interrupted = 0;
        return luaL_error(L, "interrupted");
    }
    return 0;
}

// ─────────────────────────────────────────────────────────────
// 调试 Agent 用的轻量 TCP socket 接口（仅 Linux）
// 暴露给 Lua：
//   dbg_listen(port)         → fd 或 nil,err
//   dbg_accept(server_fd)    → fd 或 nil,err
//   dbg_send(fd, str)        → true 或 nil,err
//   dbg_recv_line(fd)        → str 或 nil,err   （读到 '\n' 为止）
//   dbg_recv_n(fd, n)        → str 或 nil,err   （精确读 n 字节）
//   dbg_close(fd)            → true
// ─────────────────────────────────────────────────────────────

static int lua_dbg_listen(lua_State* L)
{
    int port = (int)luaL_checkinteger(L, 1);
    int fd = socket(AF_INET, SOCK_STREAM, 0);
    if (fd < 0) { lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2; }

    int opt = 1;
    setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

    struct sockaddr_in addr{};
    addr.sin_family      = AF_INET;
    addr.sin_addr.s_addr = INADDR_ANY;
    addr.sin_port        = htons((uint16_t)port);

    if (bind(fd, (struct sockaddr*)&addr, sizeof(addr)) < 0) {
        close(fd); lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
    if (listen(fd, 1) < 0) {
        close(fd); lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
    }
    lua_pushinteger(L, fd);
    return 1;
}

static int lua_dbg_accept(lua_State* L)
{
    int server_fd = (int)luaL_checkinteger(L, 1);
    struct sockaddr_in client{};
    socklen_t len = sizeof(client);
    int fd = accept(server_fd, (struct sockaddr*)&client, &len);
    if (fd < 0) { lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2; }
    lua_pushinteger(L, fd);
    return 1;
}

static int lua_dbg_send(lua_State* L)
{
    int fd     = (int)luaL_checkinteger(L, 1);
    size_t len = 0;
    const char* s = luaL_checklstring(L, 2, &len);
    size_t sent = 0;
    while (sent < len) {
        ssize_t n = send(fd, s + sent, len - sent, MSG_NOSIGNAL);
        if (n < 0) { lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2; }
        sent += (size_t)n;
    }
    lua_pushboolean(L, 1);
    return 1;
}

static int lua_dbg_recv_line(lua_State* L)
{
    int fd = (int)luaL_checkinteger(L, 1);
    luaL_Buffer B;
    luaL_buffinit(L, &B);
    char c;
    while (true) {
        ssize_t n = recv(fd, &c, 1, 0);
        if (n <= 0) {
            if (n == 0) { lua_pushnil(L); lua_pushstring(L, "connection closed"); return 2; }
            lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
        }
        if (c == '\n') break;
        luaL_addchar(&B, c);
    }
    luaL_pushresult(&B);
    return 1;
}

static int lua_dbg_recv_n(lua_State* L)
{
    int fd   = (int)luaL_checkinteger(L, 1);
    int need = (int)luaL_checkinteger(L, 2);
    if (need <= 0) { lua_pushstring(L, ""); return 1; }

    luaL_Buffer B;
    luaL_buffinit(L, &B);
    int got = 0;
    while (got < need) {
        char buf[4096];
        int chunk = (need - got) < (int)sizeof(buf) ? (need - got) : (int)sizeof(buf);
        ssize_t n = recv(fd, buf, (size_t)chunk, 0);
        if (n <= 0) {
            if (n == 0) { lua_pushnil(L); lua_pushstring(L, "connection closed"); return 2; }
            lua_pushnil(L); lua_pushstring(L, strerror(errno)); return 2;
        }
        luaL_addlstring(&B, buf, (size_t)n);
        got += (int)n;
    }
    luaL_pushresult(&B);
    return 1;
}

static int lua_dbg_close(lua_State* L)
{
    int fd = (int)luaL_checkinteger(L, 1);
    close(fd);
    lua_pushboolean(L, 1);
    return 1;
}

int main()
{
    signal(SIGINT, sigint_handler);

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);

    // 将 sleep 函数注册为全局函数供 Lua 调用
    lua_pushcfunction(L, lua_sleep);
    lua_setglobal(L, "sleep");

    // 注册调试 Agent 用的 TCP socket 原语
    lua_pushcfunction(L, lua_dbg_listen);    lua_setglobal(L, "dbg_listen");
    lua_pushcfunction(L, lua_dbg_accept);    lua_setglobal(L, "dbg_accept");
    lua_pushcfunction(L, lua_dbg_send);      lua_setglobal(L, "dbg_send");
    lua_pushcfunction(L, lua_dbg_recv_line); lua_setglobal(L, "dbg_recv_line");
    lua_pushcfunction(L, lua_dbg_recv_n);    lua_setglobal(L, "dbg_recv_n");
    lua_pushcfunction(L, lua_dbg_close);     lua_setglobal(L, "dbg_close");

    std::cout << "Starting Lua: lua/Entry.lua\n";

    int ret = luaL_dofile(L, "lua/Entry.lua");
    if (ret != LUA_OK) {
        const char* msg = lua_tostring(L, -1);
        // Ctrl+C 主动中断，不视为错误
        if (msg && strstr(msg, "interrupted") == nullptr) {
            std::cerr << "Lua error: " << msg << "\n";
        }
        lua_pop(L, 1);
        ret = 0;
    }

    lua_close(L);
    return ret;
}

// 运行程序: Ctrl + F5 或调试 >“开始执行(不调试)”菜单
// 调试程序: F5 或调试 >“开始调试”菜单

// 入门使用技巧: 
//   1. 使用解决方案资源管理器窗口添加/管理文件
//   2. 使用团队资源管理器窗口连接到源代码管理
//   3. 使用输出窗口查看生成输出和其他消息
//   4. 使用错误列表窗口查看错误
//   5. 转到“项目”>“添加新项”以创建新的代码文件，或转到“项目”>“添加现有项”以将现有代码文件添加到项目
//   6. 将来，若要再次打开此项目，请转到“文件”>“打开”>“项目”并选择 .sln 文件
