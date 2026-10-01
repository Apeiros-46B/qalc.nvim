#pragma once

extern "C" {
#include <lua.h>
}
#include <libqalculate/includes.h>
#include <libqalculate/Calculator.h>
#include <libqalculate/Variable.h>

namespace worker {

struct Options {
	// per-calculation options passed to calculator methods.
	// {parse,print,evaluation}.* keys in the lua table map to these
	ParseOptions parse;
	PrintOptions print;
	EvaluationOptions eval;
	AutomaticApproximation auto_approximation = AUTOMATIC_APPROXIMATION_OFF;
	AutomaticFractionFormat auto_fraction = AUTOMATIC_FRACTION_OFF;

	// calculator-owned state with no corresponding option struct field.
	// state.* keys in the lua table map to these
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

	// record locale at startup
	void set_startup_locale(const Calculator* calc);

	// read options from the lua table
	void read_lua(lua_State* L, int index);

	// apply overrides
	void apply_state(Calculator* calc) const;

	// replace overrides with those from another options struct
	void take_from(Options&& other);

private:
	bool startup_decimal_comma = false;
};

}
