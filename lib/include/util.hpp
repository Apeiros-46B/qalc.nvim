#pragma once

#include <string>
#include <utility>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

namespace lua {

class StackGuard {
	lua_State* L;
	int top;
	int return_count;

public:
	StackGuard(lua_State* L, int ret_count);
	~StackGuard();
};

void dump_stack(lua_State* L);

template <typename T>
struct Userdata {
	template <typename... Args>
	static T* push(lua_State* L, const char* metatable_name, Args&&... args) {
		void* mem = lua_newuserdata(L, sizeof(T));
		T* obj = new(mem) T(std::forward<Args>(args)...);

		luaL_getmetatable(L, metatable_name);
		lua_setmetatable(L, -2);

		return obj;
	}

	static T* check(lua_State* L, int index, const char* metatable_name) {
		void* ud = luaL_checkudata(L, index, metatable_name);
		return reinterpret_cast<T*>(ud);
	}
};

inline void push(lua_State* L, int v) {
	lua_pushinteger(L, v);
}
inline void push(lua_State* L, double v) {
	lua_pushnumber(L, v);
}
inline void push(lua_State* L, bool v) {
	lua_pushboolean(L, v);
}
inline void push(lua_State* L, const std::string& v) {
	lua_pushlstring(L, v.c_str(), v.size());
}
inline void push(lua_State* L, const char* v) {
	lua_pushstring(L, v);
}

template<typename T>
inline void push_and_set(lua_State* L, T v, const char* k) {
	lua::push(L, v);
	lua_setfield(L, -2, k);
}

template<typename T>
inline void push_and_seti(lua_State* L, T v, int i) {
	lua::push(L, v);
	lua_rawseti(L, -2, i);
}

template<typename T, typename Collection>
inline void make_array(lua_State* L, Collection& iter) {
	lua_createtable(L, static_cast<int>(iter.size()), 0);
	int i = 1;
	for (T& v : iter) {
		lua::push_and_seti(L, v, i++);
	}
}

// the callable should push one item when called with (lua_State* L, T value)
template<typename T, typename Collection, typename Callable>
inline void make_array(
	lua_State* L,
	Collection& iter,
	Callable fn
) {
	lua_createtable(L, static_cast<int>(iter.size()), 0);
	int i = 1;
	for (T& v : iter) {
		fn(L, v);
		lua_rawseti(L, -2, i++);
	}
}

template<typename T, typename U, typename... Args>
void push(lua_State* L, T&& first, U&& second, Args&&... args) {
	push(L, std::forward<T>(first));
	push(L, std::forward<U>(second), std::forward<Args>(args)...);
}

template<typename T> T pop(lua_State* L, int index);

template<> inline int pop<int>(lua_State* L, int index) {
	return (int)luaL_checkinteger(L, index);
}
template<> inline std::string pop<std::string>(lua_State* L, int index) {
	size_t len;
	const char* s = luaL_checklstring(L, index, &len);
	return std::string(s, len);
}

template<typename T> T pop_or(lua_State* L, int index, T default_val) {
	if (lua_isnoneornil(L, index)) {
		return default_val;
	} else {
		return pop<T>(L, index);
	}
}

}
