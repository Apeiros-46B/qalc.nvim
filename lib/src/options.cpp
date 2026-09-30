extern "C" {
#include <lauxlib.h>
}

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

// {{{ parse options
static void read_parse_opts(lua_State* L, int tbl, ParseOptions& o) {
	// always on, needed for dep extraction to work properly
	o.limit_implicit_multiplication = true;
	o.unknowns_enabled = true;

	lua::read(L, tbl, "variables_enabled", o.variables_enabled);
	lua::read(L, tbl, "functions_enabled", o.functions_enabled);
	lua::read(L, tbl, "units_enabled", o.units_enabled);

	lua::read(L, tbl, "dot_as_separator", o.dot_as_separator);
	lua::read(L, tbl, "comma_as_separator", o.comma_as_separator);
	lua::read(L, tbl, "brackets_as_parentheses", o.brackets_as_parentheses);
	lua::read(L, tbl, "preserve_format", o.preserve_format);

	lua::read(L, tbl, "base", o.base);
	lua::read(L, tbl, "binary_bits", o.binary_bits);
	lua::read(L, tbl, "twos_complement", o.twos_complement);
	lua::read(L, tbl, "hexadecimal_twos_complement", o.hexadecimal_twos_complement);

	lua::read_enum(L, tbl, "read_precision", 0, 2, o.read_precision);
	lua::read_enum(L, tbl, "parsing_mode", 0, 4, o.parsing_mode);
	lua::read_enum(L, tbl, "angle_unit", 0, 4, o.angle_unit);
}
// }}}

// {{{ print options
static void read_sort_opts(lua_State* L, int tbl, SortOptions& o) {
	if (!lua::get_and_push(L, tbl, "sort_options")) return;
	luaL_checktype(L, -1, LUA_TTABLE);

	int sort_tbl = lua::abs_idx(L, -1);
	lua::read(L, sort_tbl, "prefix_currencies", o.prefix_currencies);
	lua::read(L, sort_tbl, "minus_last", o.minus_last);

	lua_pop(L, 1);
}

static void read_print_opts(lua_State* L, int tbl, PrintOptions& o) {
	// for consistency with parse
	o.limit_implicit_multiplication = true;

	read_sort_opts(L, tbl, o.sort_options);

	lua::read(L, tbl, "preserve_format", o.preserve_format);
	lua::read(L, tbl, "allow_non_usable", o.allow_non_usable);

	lua::read(L, tbl, "spacious", o.spacious);
	lua::read(L, tbl, "excessive_parenthesis", o.excessive_parenthesis);
	lua::read(L, tbl, "hide_underscore_spaces", o.hide_underscore_spaces);
	lua::read(L, tbl, "spell_out_logical_operators", o.spell_out_logical_operators);
	lua::read(L, tbl, "comma_sign", o.comma_sign);
	lua::read(L, tbl, "decimalpoint_sign", o.decimalpoint_sign);
	lua::read_enum(L, tbl, "multiplication_sign", 0, 3, o.multiplication_sign);
	lua::read_enum(L, tbl, "division_sign", 0, 2, o.division_sign);
	lua::read_enum(L, tbl, "digit_grouping", 0, 2, o.digit_grouping);
	lua::read_enum(L, tbl, "use_unicode_signs", 0, 3, o.use_unicode_signs);

	lua::read(L, tbl, "abbreviate_names", o.abbreviate_names);
	lua::read(L, tbl, "use_reference_names", o.use_reference_names);
	lua::read(L, tbl, "place_units_separately", o.place_units_separately);
	lua::read(L, tbl, "use_unit_prefixes", o.use_unit_prefixes);
	lua::read(L, tbl, "use_prefixes_for_all_units", o.use_prefixes_for_all_units);
	lua::read(L, tbl, "use_prefixes_for_currencies", o.use_prefixes_for_currencies);
	lua::read(L, tbl, "use_all_prefixes", o.use_all_prefixes);
	lua::read(L, tbl, "use_denominator_prefix", o.use_denominator_prefix);

	lua::read(L, tbl, "negative_exponents", o.negative_exponents);
	lua::read(L, tbl, "halfexp_to_sqrt", o.halfexp_to_sqrt);
	lua::read(L, tbl, "exp_to_root", o.exp_to_root);
	lua::read(L, tbl, "min_exp", o.min_exp);
	lua::read_enum(L, tbl, "exp_display", 0, 3, o.exp_display);

	lua::read(L, tbl, "base", o.base);
	lua::read(L, tbl, "binary_bits", o.binary_bits);
	lua::read(L, tbl, "twos_complement", o.twos_complement);
	lua::read(L, tbl, "hexadecimal_twos_complement", o.hexadecimal_twos_complement);
	lua::read(L, tbl, "duodecimal_symbols", o.duodecimal_symbols);
	lua::read(L, tbl, "lower_case_numbers", o.lower_case_numbers);
	lua::read_enum(L, tbl, "base_display", 0, 3, o.base_display);

	lua::read(L, tbl, "indicate_infinite_series", o.indicate_infinite_series);
	lua::read(L, tbl, "show_ending_zeroes", o.show_ending_zeroes);
	lua::read(L, tbl, "preserve_precision", o.preserve_precision);
	lua::read_enum(L, tbl, "interval_display", 0, 7, o.interval_display);

	lua::read(L, tbl, "min_decimals", o.min_decimals);
	lua::read(L, tbl, "max_decimals", o.max_decimals);
	lua::read(L, tbl, "use_min_decimals", o.use_min_decimals);
	lua::read(L, tbl, "use_max_decimals", o.use_max_decimals);
	lua::read(L, tbl, "restrict_to_parent_precision", o.restrict_to_parent_precision);
	lua::read_enum(L, tbl, "rounding", 0, 10, o.rounding);

	lua::read(L, tbl, "restrict_fraction_length", o.restrict_fraction_length);
	lua::read_enum(L, tbl, "number_fraction_format", 0, 8, o.number_fraction_format);

	lua::read(L, tbl, "short_multiplication", o.short_multiplication);
	lua::read(L, tbl, "improve_division_multipliers", o.improve_division_multipliers);
	lua::read(L, tbl, "allow_factorization", o.allow_factorization);

	lua::read(L, tbl, "custom_time_zone", o.custom_time_zone);
	lua::read_enum(L, tbl, "time_zone", 0, 2, o.time_zone);
	lua::read_enum(L, tbl, "date_time_format", 0, 1, o.date_time_format);
}
// }}}

// {{{ eval options
static void read_eval_opts(lua_State* L, int tbl, EvaluationOptions& o) {
	lua::read(L, tbl, "calculate_variables", o.calculate_variables);
	lua::read(L, tbl, "calculate_functions", o.calculate_functions);
	lua::read(L, tbl, "test_comparisons", o.test_comparisons);
	lua::read(L, tbl, "isolate_x", o.isolate_x);
	lua::read(L, tbl, "assume_denominators_nonzero", o.assume_denominators_nonzero);
	lua::read(L, tbl,
		"warn_about_denominators_assumed_nonzero",
		o.warn_about_denominators_assumed_nonzero
	);
	lua::read(L, tbl,
		"transform_trigonometric_functions",
		o.transform_trigonometric_functions
	);
	lua::read_enum(L, tbl, "approximation", 0, 2, o.approximation);
	lua::read_enum(L, tbl, "interval_calculation", 0, 3, o.interval_calculation);

	lua::read(L, tbl, "keep_prefixes", o.keep_prefixes);
	lua::read(L, tbl, "keep_zero_units", o.keep_zero_units);
	lua::read(L, tbl, "sync_units", o.sync_units);
	lua::read(L, tbl, "sync_nonlinear_unit_relations", o.sync_nonlinear_unit_relations);
	lua::read(L, tbl, "local_currency_conversion", o.local_currency_conversion);
	lua::read_enum(L, tbl, "auto_post_conversion", 0, 3, o.auto_post_conversion);
	lua::read_enum(L, tbl, "mixed_units_conversion", 0, 5, o.mixed_units_conversion);

	lua::read(L, tbl, "split_squares", o.split_squares);
	lua::read(L, tbl, "reduce_divisions", o.reduce_divisions);
	lua::read(L, tbl, "combine_divisions", o.combine_divisions);
	lua::read(L, tbl, "do_polynomial_division", o.do_polynomial_division);
	lua::read(L, tbl, "expand", o.expand);
	lua::read_enum(L, tbl, "structuring", 0, 2, o.structuring);

	lua::read(L, tbl, "allow_infinite", o.allow_infinite);
	lua::read(L, tbl, "allow_complex", o.allow_complex);
	lua::read_enum(L, tbl, "complex_number_form", 0, 3, o.complex_number_form);
}
// }}}

void Options::read_lua(lua_State* L, int index) {
	index = lua::abs_idx(L, index);
	luaL_checktype(L, index, LUA_TTABLE);

	if (lua::get_and_push(L, index, "parse")) {
		luaL_checktype(L, -1, LUA_TTABLE);
		read_parse_opts(L, lua::abs_idx(L, -1), parse);
		lua_pop(L, 1);
	}
	if (lua::get_and_push(L, index, "print")) {
		luaL_checktype(L, -1, LUA_TTABLE);
		read_print_opts(L, lua::abs_idx(L, -1), print);
		lua_pop(L, 1);
	}
	if (lua::get_and_push(L, index, "evaluation")) {
		luaL_checktype(L, -1, LUA_TTABLE);
		read_eval_opts(L, lua::abs_idx(L, -1), eval);
		lua_pop(L, 1);
	}

	eval.parse_options = parse;
}

}
