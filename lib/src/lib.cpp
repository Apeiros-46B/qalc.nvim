extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

#include "options.hpp"
#include "worker.hpp"

static const luaL_Reg functions[] = {
	{ "get_defs",            worker::lua_get_defs           },
	{ "init_loop",           worker::lua_init_loop          },
	{ "set_callback",        worker::lua_set_callback       },
	{ "submit_eval_batch",   worker::lua_submit_eval_batch  },
	{ "submit_parse_batch",  worker::lua_submit_parse_batch },
	{ "set_options",         worker::lua_set_options        },
	{ "reset_options",       worker::lua_reset_options      },
	{ "option_schema",       options::lua_option_schema     },
	{ nullptr,               nullptr                        },
};

// in lua code, it is required as "qalc.lib" so this is named luaopen_qalc_lib
extern "C" int luaopen_qalc_lib(lua_State* L) {
	worker::init(L);
	luaL_newlib(L, functions);
	return 1;
}
