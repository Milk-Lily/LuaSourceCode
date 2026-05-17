cmake_minimum_required(VERSION 3.10)
project(LuaSourceCode)

set(CMAKE_CXX_STANDARD 14)

# Linux 下需要的编译选项
if(UNIX)
    add_compile_definitions(LUA_USE_LINUX)
    set(CMAKE_C_FLAGS "${CMAKE_C_FLAGS} -DLUA_USE_LINUX")
endif()

include_directories(.)

add_executable(LuaSourceCode
    lapi.c
    lauxlib.c
    lbaselib.c
    lcode.c
    lcorolib.c
    lctype.c
    ldblib.c
    ldebug.c
    ldo.c
    ldump.c
    lfunc.c
    lgc.c
    linit.c
    liolib.c
    llex.c
    lmathlib.c
    lmem.c
    loadlib.c
    lobject.c
    lopcodes.c
    loslib.c
    lparser.c
    lstate.c
    lstring.c
    lstrlib.c
    ltable.c
    ltablib.c
    ltm.c
    lundump.c
    lutf8lib.c
    lvm.c
    lzio.c
    LuaSourceCode.cpp)

# Linux 需要链接 math 和 dl 库
if(UNIX)
    target_link_libraries(LuaSourceCode m dl)
endif()

# 将 lua 脚本目录拷贝到构建目录，方便运行时找到脚本
file(COPY ${CMAKE_SOURCE_DIR}/lua DESTINATION ${CMAKE_BINARY_DIR})
