#include "options.hpp"

namespace options {

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
	print.exp_display = EXP_UPPERCASE_E;
	print.base_display = BASE_DISPLAY_NORMAL;
	print.division_sign = DIVISION_SIGN_SLASH;
	print.multiplication_sign = MULTIPLICATION_SIGN_X;
	print.spell_out_logical_operators = true;
	print.interval_display = INTERVAL_DISPLAY_SIGNIFICANT_DIGITS;

	eval.warn_about_denominators_assumed_nonzero = true;
	derive_retained_prefs();
}

void Options::derive_retained_prefs() {
	parse.parsing_mode = rpn_syntax ? PARSING_MODE_RPN : parsing_mode;

	if (!simplified_percentage) {
		parse.parsing_mode = static_cast<ParsingMode>(
			parse.parsing_mode | PARSE_PERCENT_AS_ORDINARY_CONSTANT
		);
	}

	print.use_unicode_signs = unicode ? unicode_exponents : UNICODE_SIGNS_OFF;
	eval.parse_options = parse;
}

void Options::set_decimal_separator(Calculator* calc, int mode) const {
	if (mode > 0 || (mode < 0 && startup_decimal_comma)) {
		calc->useDecimalComma();
	} else {
		calc->useDecimalPoint(parse.comma_as_separator);
	}
}

}
