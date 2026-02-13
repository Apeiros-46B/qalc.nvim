extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include "calculator.hpp"
#include "worker.hpp"

static const luaL_Reg functions[] = {
	{ "submit_job",    worker::lua_submit_job   },
	{ "set_callback",  worker::lua_set_callback },
	{ "make_instance", calc::lua_make_instance  },
	{ nullptr,         nullptr                  },
};

// in lua code, it is required as "qalc.lib" so this is named luaopen_qalc_lib
extern "C" int luaopen_qalc_lib(lua_State* L) {
	calc::init_mt(L);
	worker::init_mt(L);
	worker::init(L);
	luaL_newlib(L, functions);
	return 1;
}
