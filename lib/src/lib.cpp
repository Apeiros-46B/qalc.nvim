extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include "worker.hpp"

static const luaL_Reg functions[] = {
	{ "init_loop",     worker::lua_init_loop    },
	{ "submit_job",    worker::lua_submit_job   },
	{ "set_callback",  worker::lua_set_callback },
	{ nullptr,         nullptr                  },
};

// in lua code, it is required as "qalc.lib" so this is named luaopen_qalc_lib
extern "C" int luaopen_qalc_lib(lua_State* L) {
	worker::init_mt(L);
	worker::init(L);
	luaL_newlib(L, functions);
	return 1;
}
