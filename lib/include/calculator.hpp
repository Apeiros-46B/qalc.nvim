#pragma once

extern "C" {
#include <lua.h>
}
#include <libqalculate/Calculator.h>

namespace calc {

static const char* MT = "libqalcbridge.Calculator";
void init_mt(lua_State* L);

int lua_make_instance(lua_State* L);

struct Instance {
	Calculator* inner;

	Instance();
	~Instance();

  // for some reason, libqalculate sets a global CALCULATOR singleton when you
	// instantiate a calculator, and many functions (including destructor)
	// reference this CALCULATOR singleton, which can lead to strange issues.
	// for example, if you ever construct >=2 Calculators, there will be a
	// double free when their destructors are called. therefore, this MUST
	// be called on an Instance before operating on the inner Calculator.
	void make_current();
};

}
