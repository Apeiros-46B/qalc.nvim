#ifndef CALCULATOR_HPP_
#define CALCULATOR_HPP_

extern "C" {
#include <lua.h>
}

namespace calc {
	int init(lua_State* L);
	int eval(lua_State* L);
	int reset(lua_State* L);
	int load_defs(lua_State* L);
	int save_defs(lua_State* L);
	void init_metatables(lua_State* L);
}

#endif
