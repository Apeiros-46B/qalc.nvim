#pragma once

#include <string>
#include <utility>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
}

// matches vim.diagnostic.severity (can verify with vim.inspect())
enum class Severity: int {
	ERROR = 1,
	WARN = 2,
	INFO = 3,
	HINT = 4,
};

// matches vim.lsp.protocol.CompletionItemKind
enum class LspKind : int {
	FUNC = 3,
	VAR = 6,
	UNIT = 11,
	ENUM_MB = 20,
	CONST = 21,
};

namespace strings {

std::string preprocess_str(const std::string& text, bool align_newlines = false);

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

inline int abs_index(lua_State* L, int index) {
	return index < 0 ? lua_gettop(L) + index + 1 : index;
}

// {{{ userdata wrapper
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
// }}}

// {{{ construction helpers
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
	for (const T& v : iter) {
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

// variadic push
template<typename T, typename U, typename... Args>
void push(lua_State* L, T&& first, U&& second, Args&&... args) {
	push(L, std::forward<T>(first));
	push(L, std::forward<U>(second), std::forward<Args>(args)...);
}
// }}}

// {{{ pop helper
template<typename T> T pop(lua_State* L, int index);

template<> inline bool pop(lua_State* L, int index) {
	luaL_checktype(L, index, LUA_TBOOLEAN);
	return lua_toboolean(L, index);
}
template<> inline int pop(lua_State* L, int index) {
	return (int)luaL_checkinteger(L, index);
}
template<> inline std::string pop(lua_State* L, int index) {
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
// }}}

inline bool get_and_push(lua_State* L, int tbl, const char* k) {
	lua_getfield(L, tbl, k);
	if (lua_isnil(L, -1)) {
		lua_pop(L, 1);
		return false;
	}
	return true;
}

// specializations should not manipulate the stack
template<typename T> void _read_inner(lua_State* L, const char* k, T& tgt);

template<> inline void _read_inner(lua_State* L, const char* k, bool& tgt) {
	luaL_checktype(L, -1, LUA_TBOOLEAN);
	tgt = lua_toboolean(L, -1);
}

template<> inline void _read_inner(lua_State* L, const char* k, int& tgt) {
	tgt = static_cast<int>(luaL_checkinteger(L, -1));
}

template<> inline void _read_inner(lua_State* L, const char* k, unsigned int& tgt) {
	lua_Integer v = luaL_checkinteger(L, -1);
	if (v < 0) luaL_error(L, "%s cannot be negative", k);
	tgt = static_cast<unsigned int>(v);
}

template<> inline void _read_inner(lua_State* L, const char* k, std::string& tgt) {
	size_t sz;
	const char* v = luaL_checklstring(L, -1, &sz);
	tgt.assign(v, sz);
}

template<typename T> void read(lua_State* L, int tbl, const char* k, T& tgt) {
	if (!get_and_push(L, tbl, k)) return;
	_read_inner<T>(L, k, tgt);
	lua_pop(L, 1);
}

template<typename T> void read_enum(
	lua_State* L,
	int tbl,
	const char* k,
	int min,
	int max,
	T& tgt
) {
	if (!get_and_push(L, tbl, k)) return;

	int v = static_cast<int>(luaL_checkinteger(L, -1));
	if (v < min || v > max) {
		luaL_error(L, "%s must be between %d and %d", k, min, max);
	}
	tgt = static_cast<T>(v);

	lua_pop(L, 1);
}

}
