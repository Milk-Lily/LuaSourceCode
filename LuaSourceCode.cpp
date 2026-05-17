// LuaSourceCode.cpp : C++ 嵌入 Lua 源码工程入口（Linux）
//

#include <iostream>
#include <cstdlib>
#include <csignal>
#include <sys/select.h>

extern "C" {
#include "lua.h"
#include "lualib.h"
#include "lauxlib.h"
}

static lua_State* gL = nullptr;

// Ctrl+C 时通过 lua_sethook 在下一条 Lua 指令处注入错误，干净退出
static void sigint_handler(int)
{
    if (gL) {
        lua_sethook(gL, [](lua_State* L, lua_Debug*) {
            lua_sethook(L, nullptr, 0, 0);
            luaL_error(L, "interrupted");
        }, LUA_MASKCALL | LUA_MASKRET | LUA_MASKCOUNT, 1);
    }
}

// 注册到 Lua 的 sleep(seconds) 函数
// 使用 select 实现：Linux 信号会中断 select，使 Ctrl+C 立即响应
static int lua_sleep(lua_State* L)
{
    double seconds = luaL_checknumber(L, 1);
    struct timeval tv;
    tv.tv_sec  = (long)seconds;
    tv.tv_usec = (long)((seconds - tv.tv_sec) * 1e6);
    select(0, nullptr, nullptr, nullptr, &tv);
    return 0;
}

int main()
{
    lua_State* L = luaL_newstate();
    gL = L;
    signal(SIGINT, sigint_handler);
    luaL_openlibs(L);

    // 将 sleep 函数注册为全局函数供 Lua 调用
    lua_pushcfunction(L, lua_sleep);
    lua_setglobal(L, "sleep");

    std::cout << "Starting Lua: lua/Entry.lua\n";

    int ret = luaL_dofile(L, "lua/Entry.lua");
    if (ret != LUA_OK) {
        std::cerr << "Lua error: " << lua_tostring(L, -1) << "\n";
        lua_pop(L, 1);
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
