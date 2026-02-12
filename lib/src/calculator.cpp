#include "calculator.hpp"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

#include <libqalculate/qalculate.h>

#include <cctype>
#include <string>

static const char* meta = "libqalcbridge.Calculator";

namespace calc {

Instance::Instance() {
	this->inst = new Calculator();
	this->inst->loadGlobalDefinitions();
}

Instance::~Instance() {
	this->make_current();
	delete this->inst;
	CALCULATOR = nullptr; // prevent dangling ptr
}

void Instance::make_current() {
  if (CALCULATOR == this->inst) {
    CALCULATOR = this->inst;
	}
}

// called from lua directly
int init(lua_State* L) {
	// "handle" value (userdata) returned back to Lua.
	// when this value is no longer reachable, the calculator is freed.
	auto calc_handle = lua_newuserdata(L, 1);
	luaL_setmetatable(L, meta);

	new Calculator();
	CALCULATOR->loadExchangeRates();
	CALCULATOR->loadGlobalDefinitions();

	return 1;
}

// called from lua directly
int eval(lua_State* L) {
	const char* input = luaL_checkstring(L, -1);

	lua_createtable(L, 0, 4);

	lua_pushstring(L, CALCULATOR->calculateAndPrint(input, 2000).c_str());
	lua_setfield(L, -2, "result");

	lua_createtable(L, 2, 0);
	lua_setfield(L, -2, "info_msgs");

	lua_createtable(L, 2, 0);
	lua_setfield(L, -2, "warn_msgs");

	lua_createtable(L, 2, 0);
	lua_setfield(L, -2, "err_msgs");

	lua_getfield(L, -1, "err_msgs");  // -4
	lua_getfield(L, -2, "warn_msgs"); // -3
	lua_getfield(L, -3, "info_msgs"); // -2

	// lua is 1-indexed
	int info_i = 1;
	int warn_i = 1;
	int err_i = 1;
	CalculatorMessage* msg;

	while ((msg = CALCULATOR->message()) != nullptr) {
		lua_pushstring(L, msg->c_message());
		switch (msg->type()) {
			case MESSAGE_INFORMATION:
				lua_rawseti(L, -2, info_i++); break;
			case MESSAGE_WARNING:
				lua_rawseti(L, -3, warn_i++); break;
			case MESSAGE_ERROR:
				lua_rawseti(L, -4, err_i++); break;
		}
		CALCULATOR->nextMessage();
	}

	lua_pop(L, 3);

	return 1;
}

int reset(lua_State* L) {
	CALCULATOR->reset();
	return 0;
}

int load_defs(lua_State* L) {
	const char* file = luaL_checkstring(L, -1);
	CALCULATOR->loadDefinitions(file, true, false);
	return 0;
}

int save_defs(lua_State* L) {
	const char* file = luaL_checkstring(L, -1);
	CALCULATOR->saveVariables(file, false);
	CALCULATOR->saveUnits(file, false);
	CALCULATOR->saveFunctions(file, false);
	return 0;
}

// called from library
void init_metatables(lua_State* L) {
	luaL_newmetatable(L, meta);

	// create a destructor for the calculator singleton
	lua_pushcfunction(L, [](lua_State* L) { delete CALCULATOR; return 0; });
	lua_setfield(L, -2, "__gc");

	lua_pop(L, 1);
}

}
