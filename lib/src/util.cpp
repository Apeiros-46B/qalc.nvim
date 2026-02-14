#include "util.hpp"
#include <iostream>

extern "C" {
#include <lua.h>
}

namespace lua {

StackGuard::StackGuard(lua_State* L, int ret_count = 0):
	L(L), top(lua_gettop(L)), return_count(ret_count)
{}

StackGuard::~StackGuard() {
	int current_top = lua_gettop(L);
	int expected = top + return_count;
	if (current_top > expected) {
		lua_pop(L, current_top - expected);
	}
}

// TODO: make this do nothing in release builds
void dump_stack(lua_State* L) {
	int top = lua_gettop(L);
	std::cout << "--- stack (top: " << top << ") ---\n";
	for (int i = 1; i <= top; i++) {
		int t = lua_type(L, i);
		std::cout << i << " (" << -(top - i + 1) << "): ";
		switch (t) {
			case LUA_TSTRING:
				std::cout << "'" << lua_tostring(L, i) << "'";
				break;
			case LUA_TBOOLEAN:
				std::cout << (lua_toboolean(L, i) ? "true" : "false");
				break;
			case LUA_TNUMBER:
				std::cout << lua_tonumber(L, i);
				break;
			default:
				std::cout << lua_typename(L, t);
				break;
		}
		std::cout << "\n";
	}
	std::cout << "---------------------------\n";
}

}
