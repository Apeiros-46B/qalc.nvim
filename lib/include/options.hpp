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

	// prefs retained while a coupled control temporarily overrides them
	ParsingMode parsing_mode = PARSING_MODE_ADAPTIVE;
	bool rpn_syntax = false;
	bool unicode = true;
	int unicode_exponents = UNICODE_SIGNS_ON;

	// calculator-owned state with no corresponding option struct field
	int decimal_comma = -1;
	int precision = 10;
	int sinc = 0;
	bool binary_prefixes = false;
	bool concise_uncertainty = false;
	bool interval_arithmetic = true;
	bool variable_units = true;
	AssumptionSign assumption_sign = ASSUMPTION_SIGN_UNKNOWN;
	AssumptionType assumption_type = ASSUMPTION_TYPE_NUMBER;
	TemperatureCalculationMode temperature = TEMPERATURE_CALCULATION_HYBRID;

	Options();

	void set_startup_locale(const Calculator* calc);

	// apply calculator-owned settings on the worker thread
	void apply_state_opts_to(Calculator* calc) const;

	void derive_retained_prefs();

private:
	bool startup_decimal_comma = false;
};

struct OptionChange {
	std::size_t option_id;
	long long value; // validated resolved value (bool, int, enum, etc)
	bool reset;
};

struct ConfigUpdate {
	std::vector<OptionChange> changes;

	void apply(Options& options, Calculator* calc) const;
};

// convert lua settings table (or name array when `reset`) to validated update.
// pushes canonical overrides, reset names, and a reparse flag to lua
ConfigUpdate read_option_update(lua_State* L, int index, bool reset);

}
