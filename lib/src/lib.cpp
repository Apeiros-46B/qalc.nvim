#include "calculator.hpp"

extern "C" {
#include <lua.h>
#include <lualib.h>
#include <lauxlib.h>
}

static const luaL_Reg functions[] = {
	{ "init",      calc::init      },
	{ "eval",      calc::eval      },
	{ "reset",     calc::reset     },
	{ "load_defs", calc::load_defs },
	{ "save_defs", calc::save_defs },
	{ nullptr,     nullptr         }
};

// in lua code, it is required as "qalc.lib" so this is named luaopen_qalc_lib
extern "C" int luaopen_qalc_lib(lua_State* L) {
	calc::init_metatables(L);
	luaL_newlib(L, functions);
	return 1;
}
