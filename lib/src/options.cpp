#include <utility>

extern "C" {
#include <lauxlib.h>
}
#include <libqalculate/BuiltinFunctions.h>

#include "options.hpp"
#include "util.hpp"

namespace worker {

// qalc 5.3 cli defaults (src/qalc.cc `load_preferences`)
Options::Options() {
	parse.unknowns_enabled = true;
	parse.limit_implicit_multiplication = true;
	print.limit_implicit_multiplication = true;

	parse.angle_unit = ANGLE_UNIT_RADIANS;
	parse.comma_as_separator = false;

	print.use_min_decimals = false;
	print.use_max_decimals = false;
	print.max_decimals = 2;
	print.sort_options.minus_last = true;
	print.use_unicode_signs = UNICODE_SIGNS_ON;
	print.exp_display = EXP_UPPERCASE_E;
	print.base_display = BASE_DISPLAY_NORMAL;
	print.division_sign = DIVISION_SIGN_SLASH;
	print.multiplication_sign = MULTIPLICATION_SIGN_X;
	print.spell_out_logical_operators = true;
	print.interval_display = INTERVAL_DISPLAY_SIGNIFICANT_DIGITS;

	eval.warn_about_denominators_assumed_nonzero = true;
	eval.parse_options = parse;
}

void Options::set_startup_locale(const Calculator* calc) {
	startup_decimal_comma = calc->getDecimalPoint() == ",";
}

void Options::take_from(Options&& other) {
	// retain startup locale
	other.startup_decimal_comma = startup_decimal_comma;
	*this = std::move(other);
}

// {{{ parse options
static void read_parse_opts(lua_State* L, int tbl, ParseOptions& o) {
	// always on, needed for dep extraction to work properly
	o.limit_implicit_multiplication = true;
	o.unknowns_enabled = true;

	lua::read(L, tbl, "parse.variables_enabled", o.variables_enabled);
	lua::read(L, tbl, "parse.functions_enabled", o.functions_enabled);
	lua::read(L, tbl, "parse.units_enabled", o.units_enabled);

	lua::read(L, tbl, "parse.dot_as_separator", o.dot_as_separator);
	lua::read(L, tbl, "parse.comma_as_separator", o.comma_as_separator);
	lua::read(L, tbl, "parse.brackets_as_parentheses", o.brackets_as_parentheses);
	lua::read(L, tbl, "parse.preserve_format", o.preserve_format);

	lua::read(L, tbl, "parse.base", o.base);
	lua::read(L, tbl, "parse.binary_bits", o.binary_bits);
	lua::read(L, tbl, "parse.twos_complement", o.twos_complement);
	lua::read(L, tbl, "parse.hexadecimal_twos_complement", o.hexadecimal_twos_complement);

	lua::read_enum(L, tbl, "parse.read_precision", 0, 2, o.read_precision);
	lua::read_enum(L, tbl, "parse.parsing_mode", 0, 4, o.parsing_mode);
	lua::read_enum(L, tbl, "parse.angle_unit", 0, 4, o.angle_unit);
}
// }}}

// {{{ print options
static void read_print_opts(lua_State* L, int tbl, PrintOptions& o) {
	// for consistency with parse
	o.limit_implicit_multiplication = true;

	lua::read(L, tbl, "print.sort_options.prefix_currencies", o.sort_options.prefix_currencies);
	lua::read(L, tbl, "print.sort_options.minus_last", o.sort_options.minus_last);

	lua::read(L, tbl, "print.preserve_format", o.preserve_format);
	lua::read(L, tbl, "print.allow_non_usable", o.allow_non_usable);

	lua::read(L, tbl, "print.spacious", o.spacious);
	lua::read(L, tbl, "print.excessive_parenthesis", o.excessive_parenthesis);
	lua::read(L, tbl, "print.hide_underscore_spaces", o.hide_underscore_spaces);
	lua::read(L, tbl, "print.spell_out_logical_operators", o.spell_out_logical_operators);
	lua::read(L, tbl, "print.comma_sign", o.comma_sign);
	lua::read(L, tbl, "print.decimalpoint_sign", o.decimalpoint_sign);
	lua::read_enum(L, tbl, "print.multiplication_sign", 0, 3, o.multiplication_sign);
	lua::read_enum(L, tbl, "print.division_sign", 0, 2, o.division_sign);
	lua::read_enum(L, tbl, "print.digit_grouping", 0, 2, o.digit_grouping);
	lua::read_enum(L, tbl, "print.use_unicode_signs", 0, 3, o.use_unicode_signs);

	lua::read(L, tbl, "print.abbreviate_names", o.abbreviate_names);
	lua::read(L, tbl, "print.use_reference_names", o.use_reference_names);
	lua::read(L, tbl, "print.place_units_separately", o.place_units_separately);
	lua::read(L, tbl, "print.use_unit_prefixes", o.use_unit_prefixes);
	lua::read(L, tbl, "print.use_prefixes_for_all_units", o.use_prefixes_for_all_units);
	lua::read(L, tbl, "print.use_prefixes_for_currencies", o.use_prefixes_for_currencies);
	lua::read(L, tbl, "print.use_all_prefixes", o.use_all_prefixes);
	lua::read(L, tbl, "print.use_denominator_prefix", o.use_denominator_prefix);

	lua::read(L, tbl, "print.negative_exponents", o.negative_exponents);
	lua::read(L, tbl, "print.halfexp_to_sqrt", o.halfexp_to_sqrt);
	lua::read(L, tbl, "print.exp_to_root", o.exp_to_root);
	lua::read(L, tbl, "print.min_exp", o.min_exp);
	lua::read_enum(L, tbl, "print.exp_display", 0, 3, o.exp_display);

	lua::read(L, tbl, "print.base", o.base);
	lua::read(L, tbl, "print.binary_bits", o.binary_bits);
	lua::read(L, tbl, "print.twos_complement", o.twos_complement);
	lua::read(L, tbl, "print.hexadecimal_twos_complement", o.hexadecimal_twos_complement);
	lua::read(L, tbl, "print.duodecimal_symbols", o.duodecimal_symbols);
	lua::read(L, tbl, "print.lower_case_numbers", o.lower_case_numbers);
	lua::read_enum(L, tbl, "print.base_display", 0, 3, o.base_display);

	lua::read(L, tbl, "print.indicate_infinite_series", o.indicate_infinite_series);
	lua::read(L, tbl, "print.show_ending_zeroes", o.show_ending_zeroes);
	lua::read(L, tbl, "print.preserve_precision", o.preserve_precision);
	lua::read_enum(L, tbl, "print.interval_display", 0, 7, o.interval_display);

	lua::read(L, tbl, "print.min_decimals", o.min_decimals);
	lua::read(L, tbl, "print.max_decimals", o.max_decimals);
	lua::read(L, tbl, "print.use_min_decimals", o.use_min_decimals);
	lua::read(L, tbl, "print.use_max_decimals", o.use_max_decimals);
	lua::read(L, tbl, "print.restrict_to_parent_precision", o.restrict_to_parent_precision);
	lua::read_enum(L, tbl, "print.rounding", 0, 10, o.rounding);

	lua::read(L, tbl, "print.restrict_fraction_length", o.restrict_fraction_length);
	lua::read_enum(L, tbl, "print.number_fraction_format", 0, 8, o.number_fraction_format);

	lua::read(L, tbl, "print.short_multiplication", o.short_multiplication);
	lua::read(L, tbl, "print.improve_division_multipliers", o.improve_division_multipliers);
	lua::read(L, tbl, "print.allow_factorization", o.allow_factorization);

	lua::read(L, tbl, "print.custom_time_zone", o.custom_time_zone);
	lua::read_enum(L, tbl, "print.time_zone", 0, 2, o.time_zone);
	lua::read_enum(L, tbl, "print.date_time_format", 0, 1, o.date_time_format);
}
// }}}

// {{{ eval options
static void read_eval_opts(lua_State* L, int tbl, EvaluationOptions& o) {
	lua::read(L, tbl, "evaluation.calculate_variables", o.calculate_variables);
	lua::read(L, tbl, "evaluation.calculate_functions", o.calculate_functions);
	lua::read(L, tbl, "evaluation.test_comparisons", o.test_comparisons);
	lua::read(L, tbl, "evaluation.isolate_x", o.isolate_x);
	lua::read(L, tbl, "evaluation.assume_denominators_nonzero", o.assume_denominators_nonzero);
	lua::read(L, tbl,
		"evaluation.warn_about_denominators_assumed_nonzero",
		o.warn_about_denominators_assumed_nonzero
	);
	lua::read(L, tbl,
		"evaluation.transform_trigonometric_functions",
		o.transform_trigonometric_functions
	);
	lua::read_enum(L, tbl, "evaluation.approximation", 0, 2, o.approximation);
	lua::read_enum(L, tbl, "evaluation.interval_calculation", 0, 3, o.interval_calculation);

	lua::read(L, tbl, "evaluation.keep_prefixes", o.keep_prefixes);
	lua::read(L, tbl, "evaluation.keep_zero_units", o.keep_zero_units);
	lua::read(L, tbl, "evaluation.sync_units", o.sync_units);
	lua::read(L, tbl, "evaluation.sync_nonlinear_unit_relations", o.sync_nonlinear_unit_relations);
	lua::read(L, tbl, "evaluation.local_currency_conversion", o.local_currency_conversion);
	lua::read_enum(L, tbl, "evaluation.auto_post_conversion", 0, 3, o.auto_post_conversion);
	lua::read_enum(L, tbl, "evaluation.mixed_units_conversion", 0, 5, o.mixed_units_conversion);

	lua::read(L, tbl, "evaluation.split_squares", o.split_squares);
	lua::read(L, tbl, "evaluation.reduce_divisions", o.reduce_divisions);
	lua::read(L, tbl, "evaluation.combine_divisions", o.combine_divisions);
	lua::read(L, tbl, "evaluation.do_polynomial_division", o.do_polynomial_division);
	lua::read(L, tbl, "evaluation.expand", o.expand);
	lua::read_enum(L, tbl, "evaluation.structuring", 0, 2, o.structuring);

	lua::read(L, tbl, "evaluation.allow_infinite", o.allow_infinite);
	lua::read(L, tbl, "evaluation.allow_complex", o.allow_complex);
	lua::read_enum(L, tbl, "evaluation.complex_number_form", 0, 3, o.complex_number_form);
}
// }}}

void Options::read_lua(lua_State* L, int index) {
	index = lua::abs_index(L, index);
	luaL_checktype(L, index, LUA_TTABLE);

	read_parse_opts(L, index, parse);
	read_print_opts(L, index, print);
	read_eval_opts(L, index, eval);
	eval.parse_options = parse;

	lua::read_enum(L, index, "output.auto_approximation", 0, 3, auto_approximation);
	lua::read_enum(L, index, "output.auto_fraction", 0, 3, auto_fraction);

	lua::read(L, index, "state.decimal_comma", decimal_comma);
	if (decimal_comma < -1 || decimal_comma > 1) {
		luaL_error(L, "decimal comma must be -1, 0 or 1");
	}

	lua::read(L, index, "state.precision", precision);
	if (precision < 1) {
		luaL_error(L, "precision must be positive");
	}

	lua::read(L, index, "state.sinc", sinc);
	if (sinc != 0 && sinc != 1) {
		luaL_error(L, "sinc must be 0 or 1");
	}

	lua::read(L, index, "state.binary_prefixes", binary_prefixes);
	lua::read(L, index, "state.concise_uncertainty", concise_uncertainty);
	lua::read(L, index, "state.interval_arithmetic", interval_arithmetic);
	lua::read(L, index, "state.variable_units", variable_units);

	lua::read_enum(L, index, "state.assumptions.sign", 0, 5, assumption_sign);
	lua::read_enum(L, index, "state.assumptions.type", 2, 7, assumption_type);
	lua::read_enum(L, index, "state.temperature_calculation", 0, 2, temperature);
}

void Options::apply_state(Calculator* calc) const {
	if (decimal_comma > 0 || (decimal_comma < 0 && startup_decimal_comma)) {
		calc->useDecimalComma();
	} else {
		calc->useDecimalPoint(parse.comma_as_separator);
	}

	if (calc->getPrecision() != precision) {
		calc->setPrecision(precision);
	}

	calc->getFunctionById(FUNCTION_ID_SINC)->setDefaultValue(2, sinc ? "pi" : "");

	calc->useBinaryPrefixes(binary_prefixes ? 1 : 0);
	calc->setConciseUncertaintyInputEnabled(concise_uncertainty);
	calc->useIntervalArithmetic(interval_arithmetic);
	calc->setVariableUnitsEnabled(variable_units);

	calc->defaultAssumptions()->setSign(assumption_sign);
	calc->defaultAssumptions()->setType(assumption_type);
	calc->setTemperatureCalculationMode(temperature);
}

}
