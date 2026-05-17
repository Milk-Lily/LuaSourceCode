// LuaSourceCode.cpp : C++ 嵌入 Lua 源码工程入口（Linux）
//

#include <iostream>
#include <cstdlib>
#include <csignal>
#include <cstring>
#include <sys/select.h>

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

int main()
{
    signal(SIGINT, sigint_handler);

    lua_State* L = luaL_newstate();
    luaL_openlibs(L);

    // 将 sleep 函数注册为全局函数供 Lua 调用
    lua_pushcfunction(L, lua_sleep);
    lua_setglobal(L, "sleep");

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
