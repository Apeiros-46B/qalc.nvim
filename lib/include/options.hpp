#pragma once

#include <cstddef>
#include <vector>

extern "C" {
#include <lua.h>
}
#include <libqalculate/Calculator.h>
#include <libqalculate/Variable.h>
#include <libqalculate/includes.h>

namespace options {

int lua_option_schema(lua_State* L);

struct Options {
	// per-calculation options passed to calculator methods
	ParseOptions parse;
	PrintOptions print;
	EvaluationOptions eval;
	AutomaticApproximation auto_approximation = AUTOMATIC_APPROXIMATION_OFF;
	AutomaticFractionFormat auto_fraction = AUTOMATIC_FRACTION_OFF;
	bool caret_as_xor = false;
	bool simplified_percentage = true;
	bool complex_angle_form = false;

	// prefs retained while a coupled control temporarily overrides them
	ParsingMode parsing_mode = PARSING_MODE_ADAPTIVE;
	bool rpn_syntax = false;
	bool unicode = true;
	int unicode_exponents = UNICODE_SIGNS_ON;

	Options();

	void initialize(Calculator* calc);

	// negative mode restores the locale captured at initialization
	void set_decimal_separator(Calculator* calc, int mode) const;

	void derive_retained_prefs();

private:
	bool startup_decimal_comma = false;
};

struct OptionChange {
	std::size_t option_id;
	long long value; // validated resolved value (bool, int, enum, etc)
	bool reset;
};

// track separators after all accepted jobs so validation follows queue order.
// this is to reject conflicting separator settings so that later changes to a
// separator do not unexpectedly unmask ignore_dot and produce incorrect results
// we need to prevent this from happening:
// - enter "1.5 * 2" -> eval to 3
// - `:QalcSet ignore_dot on` -> dot is currently the decimal sep, so no effect
// - `:QalcSet decimal_comma on` -> ignore_dot now takes effect
// - re-evaluation removes the dot from 1.5, reads it as 15, and eval to 30
struct SeparatorState {
	int decimal_comma = -1;
	bool ignore_dot = false;
	bool ignore_comma = false;
	bool startup_decimal_comma = false;
};

struct ConfigUpdate {
	std::vector<OptionChange> changes;

	void apply(Options& options, Calculator* calc) const;
	SeparatorState updated_seps(SeparatorState state) const;
};

// convert lua settings table (or name array when `reset`) to validated update.
// pushes canonical overrides, reset names, and a reparse flag to lua
ConfigUpdate read_option_update(lua_State* L, int index, bool reset);

}
