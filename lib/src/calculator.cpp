#include "calculator.hpp"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

#include <libqalculate/qalculate.h>

#include <iostream>

static const char* meta = "libqalcbridge.Calculator";

// called from lua directly
int calc::init(lua_State* L) {
	// "handle" value (userdata) returned back to Lua.
	// when this value is no longer reachable, the calculator is freed.
	// we need to do this instead of implementing a destructor on specific Calculator instances because libqalculate for some reason sets a global CALCULATOR singleton when you instantiate a calculator, and if you try to free more than one instance of a Calculator, it results in a double free somewhere.
	auto calc_handle = lua_newuserdata(L, 1);
	luaL_setmetatable(L, meta);

	new Calculator();
	CALCULATOR->loadExchangeRates();
	CALCULATOR->loadGlobalDefinitions();

	return 1;
}

// called from lua directly
int calc::eval(lua_State* L) {
	const char* input = luaL_checkstring(L, -1);
	lua_pushstring(L, CALCULATOR->calculateAndPrint(input, 2000).c_str());
	return 1;
}

// called from library
void calc::init_metatables(lua_State* L) {
	luaL_newmetatable(L, meta);

	// create a destructor for 
	lua_pushstring(L, "__gc");
	lua_pushcfunction(L, [](lua_State* L) {
		delete CALCULATOR;
		std::cout << "C++: freed calculator" << std::endl;
		return 1;
	});
	lua_settable(L, -3);

	lua_pop(L, 1);
}
