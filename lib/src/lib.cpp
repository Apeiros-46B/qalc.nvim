#include "calculator.hpp"
#include "worker.hpp"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

static const luaL_Reg functions[] = {
	{ "init",      calc::init      },
	{ "eval",      calc::eval      },
	{ "reset",     calc::reset     },
	{ nullptr,     nullptr         }
};

// in lua code, it is required as "qalc.lib" so this is named luaopen_qalc_lib
extern "C" int luaopen_qalc_lib(lua_State* L) {
	calc::init_metatables(L);
	auto* worker = new worker::Worker();
	worker->init(L);
	// TODO: replace with new API
	// - init: initializes the Worker and returns the userdata with __gc hook, attaches the callback, etc
	// - get_calculator: returns a Calculator userdata
	// - eval: takes a Calculator and submits a given job, invoking the previously registered callback when done
	luaL_newlib(L, functions);
	return 1;
}
