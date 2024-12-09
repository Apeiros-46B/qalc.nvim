#include "calculator.hpp"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

static const luaL_Reg functions[] = {
	{ "new", calc::init },
	{ nullptr, nullptr }
};

extern "C" int luaopen_libqalcbridge(lua_State* L) {
	calc::init_metatables(L);

	luaL_newlib(L, functions);

	return 1;
}
