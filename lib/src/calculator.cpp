#include <cctype>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include <libqalculate/qalculate.h>

#include "calculator.hpp"
#include "util.hpp"

namespace calc {

void init_mt(lua_State* L) {
	luaL_newmetatable(L, MT);

	// create a destructor for the calculator singleton
	lua_pushcfunction(L, [](lua_State* L) {
		Instance* inst = lua::Userdata<Instance>::check(L, 1, MT);
		// do not try to delete instance! it is memory allocated by lua, not us
		inst->~Instance();
		return 0;
	});
	lua_setfield(L, -2, "__gc");

	lua_pop(L, 1);
}

// lib.make_instance()
int lua_make_instance(lua_State* L) {
	Instance* ptr = lua::Userdata<Instance>::push(L, MT);
	return 1;
}

Instance::Instance() {
	inner = new Calculator();
	inner->loadExchangeRates();
	inner->loadGlobalDefinitions();
}

Instance::~Instance() {
	make_current();
	delete inner;
	CALCULATOR = nullptr; // prevent dangling ptr
}

void Instance::make_current() {
  if (CALCULATOR == inner) {
    CALCULATOR = inner;
	}
}

}
