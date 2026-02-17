#include "util.hpp"
#include <iostream>

extern "C" {
#include <lua.h>
}

namespace strings {

// escape markdown and optionally align newlines
std::string preprocess_str(const std::string& text, bool align_newlines) {
	std::string escaped;
	escaped.reserve(text.length() + text.length() / 10);

	for (char c : text) {
		switch (c) {
			case '*':
			case '_':
			case '`':
			case '[':
			case ']':
			case '\\':
			case '~':
				escaped.push_back('\\');
				escaped.push_back(c);
				break;
			case '<':
				escaped += "&lt;";
				break;
			case '>':
				escaped += "&gt;";
				break;
			case '\n':
				if (align_newlines) {
					escaped += "\n  ";
				} else {
					escaped.push_back('\n');
				}
				break;
			default:
				escaped.push_back(c);
				break;
		}
	}
	return escaped;
}

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
