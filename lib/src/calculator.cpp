#include "calculator.hpp"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

#include <libqalculate/qalculate.h>

static const char* meta = "libqalcbridge.Calculator";

// called from lua directly
int calc::init(lua_State* L) {
	Calculator** calc = static_cast<Calculator**>(lua_newuserdata(L, sizeof *calc));
	luaL_setmetatable(L, meta);

	*calc = new Calculator();
	(**calc).loadExchangeRates();
	(**calc).loadGlobalDefinitions();

	return 1;
}

// called from lua via __gc
static int deinit(lua_State* L) {
	auto calc = static_cast<Calculator**>(luaL_checkudata(L, -1, meta));
	delete *calc;
	return 0;
}

// called from lua directly
static int eval(lua_State* L) {
	auto calc = static_cast<Calculator**>(luaL_checkudata(L, -2, meta));
	const char* input = luaL_checkstring(L, -1);
	lua_pushstring(L, (**calc).calculateAndPrint(input, 2000).c_str());
	return 1;
}

static const luaL_Reg calculator_mt[] = {
	{ "__gc", deinit },
	{ "eval", eval },
	{ nullptr, nullptr }
};

// called from library
void calc::init_metatables(lua_State* L) {
	luaL_newmetatable(L, meta);

	// mt.__index = mt
	lua_pushstring(L, "__index");
	lua_pushvalue(L, -2);
	lua_settable(L, -3);

	// mt.x = y for all x, y pairs where y is a function in calculator_mt
	luaL_setfuncs(L, calculator_mt, 0);

	lua_pop(L, 1);
}
