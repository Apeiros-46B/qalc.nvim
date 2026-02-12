#ifndef CALCULATOR_HPP_
#define CALCULATOR_HPP_

extern "C" {
#include <lua.h>
}

#include <libqalculate/Calculator.h>

namespace calc {

struct Instance {
	Calculator* inst;

	Instance();
	~Instance();

  // For some reason, libqalculate sets a global CALCULATOR singleton when you
	// instantiate a calculator, and many functions (including destructor)
	// reference this CALCULATOR singleton, which can lead to strange issues.
	// For example, if you ever construct >=2 Calculators, there will be a
	// double free when their destructors are called. Therefore, this MUST
	// be called on an Instance before operating on the inner Calculator.
	void make_current();
};

int init(lua_State* L);
int eval(lua_State* L);
int reset(lua_State* L);
int load_defs(lua_State* L);
int save_defs(lua_State* L);
void init_metatables(lua_State* L);

}

#endif
