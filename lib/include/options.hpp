#pragma once

extern "C" {
#include <lua.h>
}
#include <libqalculate/includes.h>

namespace worker {

struct Options {
	ParseOptions parse;
	PrintOptions print;
	EvaluationOptions eval;

	Options();
	void read_lua(lua_State* L, int index);
};

}
