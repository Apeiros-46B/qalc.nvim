// mostly ai generated, did not feel like writing this by hand
#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

#include <libqalculate/BuiltinFunctions.h>

#include "options.hpp"
#include "options_schema.hpp"
#include "util.hpp"

namespace options {

// values have no inherent meaning, they're just chosen to avoid collisions
// with existing valid option values
constexpr long long INTERNAL_APPROX_AUTO = -1;
constexpr long long INTERNAL_APPROX_DUAL = -2;
constexpr long long INTERNAL_FRACTION_AUTO = -1;
constexpr long long INTERNAL_FRACTION_LONG = -2;
constexpr long long INTERNAL_FRACTION_DUAL = -3;
constexpr long long INTERNAL_COMPLEX_ANGLE = -1;

Binding::Binding(Setter set, Resetter reset)
	: set(std::move(set)), reset(std::move(reset))
{}

// {{{ create bindings
static const Options& defaults() {
	static const Options options;
	return options;
}

template<typename T>
static Binding field(T Options::* member) {
	return {
		[member](Options& options, Calculator*, long long value) {
			options.*member = static_cast<T>(value);
		},
		[member](Options& options, Calculator*) {
			options.*member = defaults().*member;
		},
	};
}

template<typename Group, typename T>
static Binding field(Group Options::* group, T Group::* member) {
	return {
		[group, member](Options& options, Calculator*, long long value) {
			(options.*group).*member = static_cast<T>(value);
		},
		[group, member](Options& options, Calculator*) {
			(options.*group).*member = (defaults().*group).*member;
		},
	};
}

template<typename Set>
static Binding calculator(Set set, long long initial) {
	return {
		[set](Options&, Calculator* calc, long long value) {
			set(calc, value);
		},
		[set, initial](Options&, Calculator* calc) {
			set(calc, initial);
		},
	};
}
// }}}

static std::string lower(std::string txt) {
	for (char& c : txt) {
		c = static_cast<char>(std::tolower(static_cast<unsigned char>(c)));
	}
	return txt;
}

static std::string string_at(lua_State* L, int idx) {
	if (lua_type(L, idx) != LUA_TSTRING) {
		throw std::runtime_error("qalc: option name must be a string");
	}

	size_t len;
	const char* txt = lua_tolstring(L, idx, &len);
	return std::string(txt, len);
}

// {{{ build schema
static const std::vector<Shortcut> shortcuts = {
	{ "exact", {}, "approximation", 1, 0 },
	{ "lowercase_e", { "lowe" }, "exp_display", 0, 1 },
	{ "round_to_even", { "rndeven" }, "rounding", 0, 1 },
};

static std::vector<Option> build_schema() {
	std::vector<Option> res;

	auto add = [&](
		const char* name,
		Kind kind,
		std::vector<std::string> aliases,
		Binding binding,
		Choices choices = {},
		bool reparse = false
	) -> Option& {
		Option opt;

		opt.name = name;
		opt.kind = kind;
		opt.aliases = std::move(aliases);
		opt.binding = std::move(binding);

		opt.choices = std::move(choices);
		opt.reparse = reparse;

		res.push_back(std::move(opt));
		return res.back();
	};

	const Choices bases = {
		{ -26, BASE_BIJECTIVE_26, { "b26", "bijective" } },
		{ -20, BASE_BINARY_DECIMAL, { "bcd" } },
		{ 2, BASE_BINARY, { "bin", "binary" } },
		{ -33, BASE_FP128, { "binary128", "fp128" } },
		{ -30, BASE_FP16, { "binary16", "fp16" } },
		{ -31, BASE_FP32, { "binary32", "float", "fp32" } },
		{ -32, BASE_FP64, { "binary64", "double", "fp64" } },
		{ 10, BASE_DECIMAL, { "dec", "decimal" } },
		{ 12, BASE_DUODECIMAL, { "duo", "duodecimal" } },
		{ -8, BASE_E, { "e" } },
		{ -34, BASE_FP80, { "fp80" } },
		{ -5, BASE_GOLDEN_RATIO, { "golden", "golden_ratio", "φ" } },
		{ 16, BASE_HEXADECIMAL, { "hex", "hexadecimal" } },
		{ 70, BASE_LATITUDE, { "latitude" } },
		{ 71, BASE_LATITUDE_2, { "latitude2" } },
		{ 72, BASE_LONGITUDE, { "longitude" } },
		{ 73, BASE_LONGITUDE_2, { "longitude2" } },
		{ 8, BASE_OCTAL, { "oct", "octal" } },
		{ -7, BASE_PI, { "pi", "π" } },
		{ -1, BASE_ROMAN_NUMERALS, { "roman" } },
		{ 60, BASE_SEXAGESIMAL, { "sexa", "sexagesimal" } },
		{ 62, BASE_SEXAGESIMAL_2, { "sexa2", "sexagesimal2" } },
		{ 63, BASE_SEXAGESIMAL_3, { "sexa3", "sexagesimal3" } },
		{ -9, BASE_SQRT2, { "sqrt(2)", "sqrt2", "√2" } },
		{ -6, BASE_SUPER_GOLDEN_RATIO, { "supergolden", "supergolden_ratio", "ψ" } },
		{ -2, BASE_TIME, { "time" } },
		{ -4, BASE_UNICODE, { "unicode" } },
	};

	Choices input_bases;
	for (const auto& base : bases) {
		const auto v = base.input;
		if (v == -1 || v == -4 || (v >= -9 && v <= -5)
			|| v == -20 || v == -26 || (v >= 2 && v <= 36)) {
			input_bases.push_back(base);
		}
	}

	add("abbreviations", Kind::BOOLEAN, { "abbr", "abbrev" },
		field(&Options::print, &PrintOptions::abbreviate_names));

	add("algebra_mode", Kind::ENUM, { "alg" },
		Binding{ [](Options& o, Calculator*, long long v) {
			o.eval.structuring = static_cast<StructuringMode>(v);
			o.print.allow_factorization = v == STRUCTURING_FACTORIZE;
		},
		[](Options& o, Calculator*) {
			o.eval.structuring = defaults().eval.structuring;
			o.print.allow_factorization = defaults().print.allow_factorization;
		} },
		{
			{ 0, STRUCTURING_NONE, { "none" } },
			{ 1, STRUCTURING_EXPAND, { "expand", "simplify" } },
			{ 2, STRUCTURING_FACTORIZE, { "factor", "factorize" } },
		});

	add("all_prefixes", Kind::BOOLEAN, { "allpref" },
		field(&Options::print, &PrintOptions::use_all_prefixes));

	add("angle_unit", Kind::ENUM, { "angle" },
		field(&Options::parse, &ParseOptions::angle_unit),
		{
			{ 0, ANGLE_UNIT_NONE, { "none" } },
			{ 1, ANGLE_UNIT_RADIANS, { "rad", "radians" } },
			{ 2, ANGLE_UNIT_DEGREES, { "deg", "degrees" } },
			{ 3, ANGLE_UNIT_GRADIANS, { "gra", "gradians" } },
		},
		true);

	add("approximation", Kind::ENUM, { "appr", "approx" },
		Binding{ [](Options& o, Calculator*, long long v) {
			o.eval.approximation = (v == INTERNAL_APPROX_AUTO
				|| v == INTERNAL_APPROX_DUAL)
				? APPROXIMATION_TRY_EXACT : static_cast<ApproximationMode>(v);
			o.auto_approximation = AUTOMATIC_APPROXIMATION_OFF;
			if (v == INTERNAL_APPROX_AUTO) {
				o.auto_approximation = AUTOMATIC_APPROXIMATION_AUTO;
			} else if (v == INTERNAL_APPROX_DUAL) {
				o.auto_approximation = AUTOMATIC_APPROXIMATION_DUAL;
			}
		},
		[](Options& o, Calculator*) {
			o.eval.approximation = defaults().eval.approximation;
			o.auto_approximation = defaults().auto_approximation;
		} },
		{
			{ -1, INTERNAL_APPROX_AUTO, { "auto" } },
			{ 0, APPROXIMATION_EXACT, { "exact" } },
			{ 1, APPROXIMATION_TRY_EXACT, { "try", "try_exact" } },
			{ 2, APPROXIMATION_APPROXIMATE, { "approx", "approximate" } },
			{ 3, INTERNAL_APPROX_DUAL, { "dual" } },
		});

	add("assume_nonzero_denominators", Kind::BOOLEAN, { "nzd" },
		field(&Options::eval, &EvaluationOptions::assume_denominators_nonzero));

	add("assumption_sign", Kind::ENUM, {},
		calculator([](Calculator* calc, long long v) {
			calc->defaultAssumptions()->setSign(static_cast<AssumptionSign>(v));
		}, ASSUMPTION_SIGN_UNKNOWN),
		{
			{ 0, ASSUMPTION_SIGN_UNKNOWN, { "none", "unknown" } },
			{ 1, ASSUMPTION_SIGN_POSITIVE, { "pos", "positive" } },
			{ 2, ASSUMPTION_SIGN_NONNEGATIVE, { "nneg", "non_negative" } },
			{ 3, ASSUMPTION_SIGN_NEGATIVE, { "neg", "negative" } },
			{ 4, ASSUMPTION_SIGN_NONPOSITIVE, { "non_positive", "npos" } },
			{ 5, ASSUMPTION_SIGN_NONZERO, { "non_zero", "nz" } },
		},
		true);

	add("assumption_type", Kind::ENUM, {},
		calculator([](Calculator* calc, long long v) {
			calc->defaultAssumptions()->setType(static_cast<AssumptionType>(v));
		}, ASSUMPTION_TYPE_REAL),
		{
			{ 2, ASSUMPTION_TYPE_NUMBER, { "complex", "cplx", "num", "number" } },
			{ 4, ASSUMPTION_TYPE_REAL, { "real" } },
			{ 5, ASSUMPTION_TYPE_RATIONAL, { "rat", "rational" } },
			{ 6, ASSUMPTION_TYPE_INTEGER, { "int", "integer" } },
			{ 7, ASSUMPTION_TYPE_BOOLEAN, { "bool", "boolean" } },
		},
		true);

	add("autoconversion", Kind::ENUM, { "conv" },
		Binding{ [](Options& o, Calculator*, long long v) {
			const AutoPostConversion conversion[] = {
				POST_CONVERSION_NONE, POST_CONVERSION_OPTIMAL,
				POST_CONVERSION_BASE, POST_CONVERSION_OPTIMAL_SI,
				POST_CONVERSION_NONE,
			};
			o.eval.auto_post_conversion = conversion[v];
			o.eval.mixed_units_conversion = v == 0
				? MIXED_UNITS_CONVERSION_NONE : MIXED_UNITS_CONVERSION_DEFAULT;
		},
		[](Options& o, Calculator*) {
			o.eval.auto_post_conversion = defaults().eval.auto_post_conversion;
			o.eval.mixed_units_conversion = defaults().eval.mixed_units_conversion;
		} },
		{
			{ 0, 0, { "none" } },
			{ 1, 1, { "optimal" } },
			{ 2, 2, { "base" } },
			{ 3, 3, { "best", "optimalsi", "si" } },
			{ 4, 4, { "mixed" } },
		});

	add("base_display", Kind::ENUM, { "basedisp" },
		field(&Options::print, &PrintOptions::base_display),
		{
			{ 0, BASE_DISPLAY_NONE, { "none" } },
			{ 1, BASE_DISPLAY_NORMAL, { "normal" } },
			{ 2, BASE_DISPLAY_ALTERNATIVE, { "alternative" } },
		});

	{
		auto& opt = add("binary_bits", Kind::INTEGER, { "bits" },
			Binding{ [](Options& o, Calculator*, long long v) {
				o.parse.binary_bits = v;
				o.print.binary_bits = v;
			},
			[](Options& o, Calculator*) {
				o.parse.binary_bits = defaults().parse.binary_bits;
				o.print.binary_bits = defaults().print.binary_bits;
			} },
			{
				{ 0, 0, { "auto" } },
			},
			true);
		opt.min = 0;
		opt.max = 4294967295LL;
		opt.excluded = { 1 };
	}

	add("binary_prefixes", Kind::BOOLEAN, { "binpref" },
		calculator([](Calculator* calc, long long v) {
			calc->useBinaryPrefixes(v ? 1 : 0);
		}, false));

	add("calculate_functions", Kind::BOOLEAN, { "calcfunc" },
		field(&Options::eval, &EvaluationOptions::calculate_functions));

	add("calculate_variables", Kind::BOOLEAN, { "calcvar" },
		field(&Options::eval, &EvaluationOptions::calculate_variables));

	add("caret_as_xor", Kind::BOOLEAN, { "xor^" },
		field(&Options::caret_as_xor), {}, true);

	add("complex_form", Kind::ENUM, { "cplxform" },
		Binding{ [](Options& o, Calculator*, long long v) {
			o.complex_angle_form = v == INTERNAL_COMPLEX_ANGLE;
			o.eval.complex_number_form = o.complex_angle_form
				? COMPLEX_NUMBER_FORM_CIS : static_cast<ComplexNumberForm>(v);
		}, [](Options& o, Calculator*) {
			o.complex_angle_form = defaults().complex_angle_form;
			o.eval.complex_number_form = defaults().eval.complex_number_form;
		} },
		{
			{ 0, COMPLEX_NUMBER_FORM_RECTANGULAR, { "cartesian", "rect", "rectangular" } },
			{ 1, COMPLEX_NUMBER_FORM_EXPONENTIAL, { "exp", "exponential" } },
			{ 2, COMPLEX_NUMBER_FORM_POLAR, { "polar" } },
			{ 3, COMPLEX_NUMBER_FORM_CIS, { "cis" } },
			{ 4, INTERNAL_COMPLEX_ANGLE, { "angle", "phasor" } },
		});

	add("complex_numbers", Kind::BOOLEAN, { "cplx" },
		field(&Options::eval, &EvaluationOptions::allow_complex));

	add("concise_uncertainty", Kind::BOOLEAN, { "concise" },
		calculator([](Calculator* calc, long long v) {
			calc->setConciseUncertaintyInputEnabled(v);
		}, false),
		{},
		true);

	add("currency_conversion", Kind::BOOLEAN, { "curconv" },
		field(&Options::eval, &EvaluationOptions::local_currency_conversion));

	add("decimal_comma", Kind::ENUM, {},
		Binding{ [](Options& o, Calculator* calc, long long v) {
			o.set_decimal_separator(calc, v);
		}, [](Options& o, Calculator* calc) {
			o.set_decimal_separator(calc, -1);
		} },
		{
			{ -1, -1, { "locale" } },
			{ 0, 0, { "off" } },
			{ 1, 1, { "on" } },
		},
		true);

	add("denominator_prefixes", Kind::BOOLEAN, { "denpref" },
		field(&Options::print, &PrintOptions::use_denominator_prefix));

	add("digit_grouping", Kind::ENUM, { "group" },
		field(&Options::print, &PrintOptions::digit_grouping),
		{
			{ 0, DIGIT_GROUPING_NONE, { "none", "off" } },
			{ 1, DIGIT_GROUPING_STANDARD, { "on", "standard" } },
			{ 2, DIGIT_GROUPING_LOCALE, { "locale" } },
#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 13)
			{ 3, DIGIT_GROUPING_UNDERSCORE, { "underscore" } },
#endif
		});

	add("division_sign", Kind::ENUM, { "divsign" },
		field(&Options::print, &PrintOptions::division_sign),
		{
			{ 0, DIVISION_SIGN_SLASH, { "/" } },
			{ 1, DIVISION_SIGN_DIVISION_SLASH, { "⁄" } },
			{ 2, DIVISION_SIGN_DIVISION, { "÷" } },
		});

	add("duodecimal_symbols", Kind::BOOLEAN, { "duosyms" },
		field(&Options::print, &PrintOptions::duodecimal_symbols));

	add("excessive_parentheses", Kind::BOOLEAN, { "expar" },
		field(&Options::print, &PrintOptions::excessive_parenthesis));

	add("exp_display", Kind::ENUM, { "edisp" },
		field(&Options::print, &PrintOptions::exp_display),
		{
			{ 0, EXP_UPPERCASE_E, { "E" } },
			{ 1, EXP_LOWERCASE_E, { "e" } },
			{ 2, EXP_POWER_OF_10, { "10", "pow", "pow10", "power", "power_of_10" } },
		});

	add("fractions", Kind::ENUM, { "fr" },
		Binding{ [](Options& o, Calculator*, long long v) {
			o.print.number_fraction_format = static_cast<NumberFractionFormat>(v);
			o.print.restrict_fraction_length =
				v == FRACTION_FRACTIONAL || v == FRACTION_COMBINED;
			o.auto_fraction = AUTOMATIC_FRACTION_OFF;
			if (v == INTERNAL_FRACTION_AUTO || v == INTERNAL_FRACTION_DUAL) {
				o.print.number_fraction_format = FRACTION_DECIMAL;
				o.auto_fraction = v == INTERNAL_FRACTION_AUTO
					? AUTOMATIC_FRACTION_AUTO : AUTOMATIC_FRACTION_DUAL;
			} else if (v == INTERNAL_FRACTION_LONG) {
				o.print.number_fraction_format = FRACTION_FRACTIONAL;
			}
		},
		[](Options& o, Calculator*) {
			o.print.number_fraction_format = defaults().print.number_fraction_format;
			o.print.restrict_fraction_length = defaults().print.restrict_fraction_length;
			o.auto_fraction = defaults().auto_fraction;
		} },
		{
			{ -1, INTERNAL_FRACTION_AUTO, { "auto" } },
			{ 0, FRACTION_DECIMAL, { "off" } },
			{ 1, FRACTION_DECIMAL_EXACT, { "exact" } },
			{ 2, FRACTION_FRACTIONAL, { "on" } },
			{ 3, FRACTION_COMBINED, { "combined", "mixed" } },
			{ 4, INTERNAL_FRACTION_LONG, { "long" } },
			{ 5, INTERNAL_FRACTION_DUAL, { "dual" } },
			{ 6, FRACTION_FRACTIONAL_FIXED_DENOMINATOR, {} },
			{ 7, FRACTION_COMBINED_FIXED_DENOMINATOR, {} },
#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 3)
			{ 8, FRACTION_PERCENT, { "%", "percent" } },
			{ 9, FRACTION_PERMILLE, { "permille", "‰" } },
			{ 10, FRACTION_PERMYRIAD, { "permyriad", "‱" } },
#endif
		});

	add("functions", Kind::BOOLEAN, { "func" },
		field(&Options::parse, &ParseOptions::functions_enabled),
		{},
		true);

	add("hexadecimal_twos", Kind::BOOLEAN, { "hextwos" },
		field(&Options::print, &PrintOptions::hexadecimal_twos_complement));

	add("hexadecimal_twos_input", Kind::BOOLEAN, { "hextwosin" },
		field(&Options::parse, &ParseOptions::hexadecimal_twos_complement),
		{},
		true);

	add("ignore_comma", Kind::BOOLEAN, { "nocomma" },
		Binding{ [](Options& o, Calculator* calc, long long v) {
			o.parse.comma_as_separator = v;
			if (calc->getDecimalPoint() != ",") calc->useDecimalPoint(v);
		}, [](Options& o, Calculator* calc) {
			o.parse.comma_as_separator = defaults().parse.comma_as_separator;
			if (calc->getDecimalPoint() != ",") {
				calc->useDecimalPoint(o.parse.comma_as_separator);
			}
		} },
		{},
		true).coupling =
#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 2)
		Coupling::SEPARATORS;
#else
		Coupling::NONE;
#endif

	add("ignore_dot", Kind::BOOLEAN, { "nodot" },
		field(&Options::parse, &ParseOptions::dot_as_separator),
		{},
		true);

	add("infinite_numbers", Kind::BOOLEAN, { "inf" },
		field(&Options::eval, &EvaluationOptions::allow_infinite));

	add("imaginary_j", Kind::BOOLEAN, { "imgj" },
		calculator([](Calculator* calc, long long v) {
			auto* imaginary = calc->getVariableById(VARIABLE_ID_I);
			if (bool(v) == (imaginary->hasName("j") > 0)) return;

			if (v) {
				ExpressionName name = imaginary->getName(1);
				name.name = "j";
				name.reference = false;
				imaginary->addName(name, 1, true);
			} else {
				imaginary->clearNonReferenceNames();
			}
			imaginary->setChanged(false);
		}, false), {}, true);

	add("input_base", Kind::BASE, { "inbase" },
		field(&Options::parse, &ParseOptions::base),
		input_bases,
		true);

	add("interval_arithmetic", Kind::BOOLEAN, { "ia", "interval" },
		calculator([](Calculator* calc, long long v) {
			calc->useIntervalArithmetic(v);
		}, true));

	add("interval_calculation", Kind::ENUM, { "ic", "uncertainty_propagation", "up" },
		field(&Options::eval, &EvaluationOptions::interval_calculation),
		{
			{ 0, INTERVAL_CALCULATION_NONE, { "none" } },
			{ 1, INTERVAL_CALCULATION_VARIANCE_FORMULA, { "variance", "variance_formula" } },
			{ 2, INTERVAL_CALCULATION_INTERVAL_ARITHMETIC, { "interval_arithmetic", "iv" } },
			{ 3, INTERVAL_CALCULATION_SIMPLE_INTERVAL_ARITHMETIC, {} },
		});

	add("interval_display", Kind::ENUM, { "ivdisp" },
		field(&Options::print, &PrintOptions::interval_display),
		{
			{ 0, INTERVAL_DISPLAY_SIGNIFICANT_DIGITS, { "adaptive" } },
			{ 1, INTERVAL_DISPLAY_SIGNIFICANT_DIGITS, { "significant" } },
			{ 2, INTERVAL_DISPLAY_INTERVAL, { "interval" } },
			{ 3, INTERVAL_DISPLAY_PLUSMINUS, { "plusminus" } },
			{ 4, INTERVAL_DISPLAY_MIDPOINT, { "midpoint" } },
			{ 5, INTERVAL_DISPLAY_LOWER, { "lower" } },
			{ 6, INTERVAL_DISPLAY_UPPER, { "upper" } },
			{ 7, INTERVAL_DISPLAY_CONCISE, { "concise" } },
			{ 8, INTERVAL_DISPLAY_RELATIVE, { "relative" } },
		});

	add("lowercase_numbers", Kind::BOOLEAN, { "lownum" },
		field(&Options::print, &PrintOptions::lower_case_numbers));

	{
		auto& opt = add("max_decimals", Kind::INTEGER, { "maxdeci" },
			Binding{ [](Options& o, Calculator*, long long v) {
				o.print.use_max_decimals = v >= 0;
				if (v >= 0) o.print.max_decimals = v;
			},
			[](Options& o, Calculator*) {
				o.print.use_max_decimals = defaults().print.use_max_decimals;
				o.print.max_decimals = defaults().print.max_decimals;
			} },
			{
				{ -1, -1, { "off" } },
			});
		opt.min = -1;
	}

	{
		auto& opt = add("min_decimals", Kind::INTEGER, { "mindeci" },
			Binding{ [](Options& o, Calculator*, long long v) {
				o.print.use_min_decimals = v >= 0;
				o.print.min_decimals = std::max(0LL, v);
			},
			[](Options& o, Calculator*) {
				o.print.use_min_decimals = defaults().print.use_min_decimals;
				o.print.min_decimals = defaults().print.min_decimals;
			} },
			{
				{ -1, -1, { "off" } },
			});
		opt.min = -1;
	}

	add("minus_last", Kind::BOOLEAN, { "minlast" },
		Binding{ [](Options& o, Calculator*, long long v) {
			o.print.sort_options.minus_last = v;
		},
		[](Options& o, Calculator*) {
			o.print.sort_options.minus_last = defaults().print.sort_options.minus_last;
		} });

	add("multiplication_sign", Kind::ENUM, { "mulsign" },
		field(&Options::print, &PrintOptions::multiplication_sign),
		{
			{ 0, MULTIPLICATION_SIGN_ASTERISK, { "*" } },
			{ 1, MULTIPLICATION_SIGN_DOT, { ".", "⋅" } },
			{ 2, MULTIPLICATION_SIGN_X, { "x", "×" } },
			{ 3, MULTIPLICATION_SIGN_ALTDOT, { "·" } },
		});

	add("output_base", Kind::BASE, { "base", "outbase" },
		field(&Options::print, &PrintOptions::base),
		bases);

	add("parsing_mode", Kind::ENUM, { "parse", "syntax" },
		field(&Options::parsing_mode),
		{
			{ 0, PARSING_MODE_ADAPTIVE, { "adaptive" } },
			{ 1, PARSING_MODE_IMPLICIT_MULTIPLICATION_FIRST, { "implicit_first" } },
			{ 2, PARSING_MODE_CONVENTIONAL, { "conventional" } },
			{ 3, PARSING_MODE_CHAIN, { "chain" } },
			{ 4, PARSING_MODE_RPN, { "rpn" } },
		},
		true).coupling = Coupling::PARSING_MODE;

	add("place_units_separately", Kind::BOOLEAN, { "unitsep" },
		field(&Options::print, &PrintOptions::place_units_separately));

	{
		auto& opt = add("precision", Kind::INTEGER, { "prec" },
			calculator([](Calculator* calc, long long v) {
				if (calc->getPrecision() != v) calc->setPrecision(v);
			}, 10));
		opt.min = 1;
	}

	add("prefixes", Kind::BOOLEAN, { "pref", "prefix" },
		field(&Options::print, &PrintOptions::use_unit_prefixes));

	add("read_precision", Kind::ENUM, { "readprec" },
		field(&Options::parse, &ParseOptions::read_precision),
		{
			{ 0, DONT_READ_PRECISION, { "off" } },
			{ 1, ALWAYS_READ_PRECISION, { "always" } },
			{ 2, READ_PRECISION_WHEN_DECIMALS, { "on", "when_decimals" } },
		},
		true);

#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 6)
	add("repeating_decimals", Kind::ENUM, { "repeating_decimal", "repdeci" },
		field(&Options::print, &PrintOptions::indicate_infinite_series),
		{
			{ 0, REPEATING_DECIMALS_OFF, { "off" } },
			{ 1, REPEATING_DECIMALS_ELLIPSIS, { "on", "ellipsis" } },
			{ 2, REPEATING_DECIMALS_OVERLINE, { "overline" } },
		}).accept_boolean = true;
#else
	add("repeating_decimals", Kind::BOOLEAN, { "repeating_decimal", "repdeci" },
		field(&Options::print, &PrintOptions::indicate_infinite_series));
#endif

	add("rounding", Kind::ENUM, { "round" },
		field(&Options::print, &PrintOptions::rounding),
		{
			{ 0, ROUNDING_HALF_AWAY_FROM_ZERO, { "half_away_from_zero", "standard" } },
			{ 1, ROUNDING_HALF_TO_EVEN, { "even", "half_to_even", "round_to_even" } },
			{ 2, ROUNDING_TOWARD_ZERO, { "toward_zero", "truncate" } },
			{ 3, ROUNDING_HALF_TO_ODD, { "half_to_odd" } },
			{ 4, ROUNDING_HALF_TOWARD_ZERO, { "half_toward_zero" } },
			{ 5, ROUNDING_HALF_UP, { "half_up" } },
			{ 6, ROUNDING_HALF_DOWN, { "half_down" } },
			{ 7, ROUNDING_HALF_RANDOM, { "half_random" } },
			{ 8, ROUNDING_AWAY_FROM_ZERO, { "away_from_zero" } },
			{ 9, ROUNDING_UP, { "up" } },
			{ 10, ROUNDING_DOWN, { "down" } },
		});

	add("rpn_syntax", Kind::BOOLEAN, { "rpnsyn" },
		field(&Options::rpn_syntax),
		{},
		true);

	{
		auto& opt = add("scientific_notation", Kind::INTEGER, { "exp", "exp_mode" },
			field(&Options::print, &PrintOptions::min_exp),
			{
				{ -1, -1, { "auto" } },
#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 3)
				{ -3, -3, { "eng", "engineering" } },
#else
				{ -3, -3, { "engineering" } },
#endif
				{ 0, 0, { "off" } },
				{ 1, 1, { "pure" } },
#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 3)
				{ 3, 3, { "sci", "scientific" } },
#else
				{ 3, 3, { "scientific" } },
#endif
			});
		opt.min = -2147483648;
		for (const char* value : { "E", "e", "pow", "pow10", "power", "power_of_10" }) {
			opt.redirects.emplace(value, "exp_display");
		}
	}

	add("short_multiplication", Kind::BOOLEAN, { "shortmul" },
		field(&Options::print, &PrintOptions::short_multiplication));

	add("show_ending_zeroes", Kind::BOOLEAN, { "zeroes" },
		field(&Options::print, &PrintOptions::show_ending_zeroes));

	add("show_negative_exponents", Kind::BOOLEAN, { "negexp" },
		field(&Options::print, &PrintOptions::negative_exponents));

	add("simplified_percentage", Kind::BOOLEAN, { "percent" },
		field(&Options::simplified_percentage), {}, true);

	add("sinc", Kind::ENUM, {},
		calculator([](Calculator* calc, long long v) {
			calc->getFunctionById(FUNCTION_ID_SINC)->setDefaultValue(2, v ? "pi" : "");
		}, 0),
		{
			{ 0, 0, { "unnormalized" } },
			{ 1, 1, { "normalized" } },
		});

	add("spacious", Kind::BOOLEAN, { "space" },
		field(&Options::print, &PrintOptions::spacious));

	add("spell_out_logical", Kind::BOOLEAN, { "spellout" },
		field(&Options::print, &PrintOptions::spell_out_logical_operators));

	add("sync_units", Kind::BOOLEAN, { "sync" },
		field(&Options::eval, &EvaluationOptions::sync_units));

	add("temperature_calculation", Kind::ENUM, { "temp" },
		calculator([](Calculator* calc, long long v) {
			calc->setTemperatureCalculationMode(static_cast<TemperatureCalculationMode>(v));
		}, TEMPERATURE_CALCULATION_HYBRID),
		{
			{ 0, TEMPERATURE_CALCULATION_HYBRID, { "hybrid" } },
			{ 1, TEMPERATURE_CALCULATION_ABSOLUTE, { "absolute" } },
			{ 2, TEMPERATURE_CALCULATION_RELATIVE, { "relative" } },
		});

	add("twos_complement", Kind::BOOLEAN, { "twos" },
		field(&Options::print, &PrintOptions::twos_complement));

	add("twos_complement_input", Kind::BOOLEAN,
#if QALCULATE_MAJOR_VERSION > 5 || (QALCULATE_MAJOR_VERSION == 5 && QALCULATE_MINOR_VERSION >= 10)
		{ "twos_input", "twosin" },
#else
		{ "twosin" },
#endif
		field(&Options::parse, &ParseOptions::twos_complement),
		{},
		true);

	add("unicode", Kind::BOOLEAN, { "uni" },
		field(&Options::unicode));

	add("unicode_exponents", Kind::ENUM, { "uniexp" },
		field(&Options::unicode_exponents),
		{
			{ 0, UNICODE_SIGNS_WITHOUT_EXPONENTS, { "off" } },
			{ 1, UNICODE_SIGNS_ON, { "on" } },
			{ 2, UNICODE_SIGNS_ONLY_UNIT_EXPONENTS, { "units" } },
		});

	add("units", Kind::BOOLEAN, { "unit" },
		field(&Options::parse, &ParseOptions::units_enabled),
		{},
		true);

	add("variable_units", Kind::BOOLEAN, { "varunits" },
		calculator([](Calculator* calc, long long v) {
			calc->setVariableUnitsEnabled(v);
		}, true));

	add("variables", Kind::BOOLEAN, { "var" },
		field(&Options::parse, &ParseOptions::variables_enabled),
		{},
		true);

	add("warn_nonzero_denominators", Kind::BOOLEAN, { "warnnzd" },
		field(&Options::eval, &EvaluationOptions::warn_about_denominators_assumed_nonzero));

	return res;
}
// }}}

static const std::vector<Option>& schema() {
	static const auto opts = build_schema();
	return opts;
}

void Options::initialize(Calculator* calc) {
	startup_decimal_comma = calc->getDecimalPoint() == ",";
	for (const auto& opt : schema()) {
		opt.binding.reset(*this, calc);
	}
	derive_retained_prefs();
}

static const Option& find_opt(const std::string& name) {
	const std::string key = lower(name);

	for (const auto& opt : schema()) {
		if (key == opt.name || std::find(opt.aliases.begin(), opt.aliases.end(), key) != opt.aliases.end()) {
			return opt;
		}
	}

	throw std::runtime_error("qalc: unknown option " + name);
}

// {{{ choice lookup and input parsing
const Choice* Option::find_choice(const std::string& text) const {
	for (const auto& choice : choices) {
		for (const auto& label : choice.labels) {
			if (label == text) return &choice;
		}
	}

	const auto folded = lower(text);
	for (const auto& choice : choices) {
		for (const auto& label : choice.labels) {
			if (label == folded) return &choice;
		}
	}

	return nullptr;
}

const Choice* Option::find_choice(long long input) const {
	for (const auto& choice : choices) {
		if (choice.input == input) return &choice;
	}

	return nullptr;
}

std::vector<std::string> Option::candidates() const {
	std::vector<std::string> result;

	for (const auto& choice : choices) {
		result.insert(result.end(), choice.labels.begin(), choice.labels.end());
		if (kind == Kind::ENUM) {
			result.push_back(std::to_string(choice.input));
		}
	}

	if (kind == Kind::BOOLEAN || accept_boolean) {
		for (const char* value : { "on", "off", "true", "false", "0", "1" }) {
			result.push_back(value);
		}
	}

	for (const auto& redirect : redirects) {
		result.push_back(redirect.first);
	}

	std::sort(result.begin(), result.end());
	result.erase(std::unique(result.begin(), result.end()), result.end());

	return result;
}

static bool read_boolean(lua_State* L, int index, bool& result) {
	const int type = lua_type(L, index);
	if (type == LUA_TBOOLEAN) {
		result = lua_toboolean(L, index);
		return true;
	}

	if (type == LUA_TNUMBER) {
		const double number = lua_tonumber(L, index);
		if (number != 0 && number != 1) return false;
		result = number != 0;
		return true;
	}

	if (type != LUA_TSTRING) return false;
	const auto text = lower(string_at(L, index));
	if (text == "on" || text == "yes" || text == "true" || text == "1") {
		result = true;
		return true;
	}

	if (text == "off" || text == "no" || text == "false" || text == "0") {
		result = false;
		return true;
	}

	return false;
}

Assignment Assignment::from_choice(const Option& opt, const Choice& choice) {
	return { &opt, choice.value, false,
		choice.labels.empty() ? "" : choice.labels.front(), choice.input };
}

Assignment Assignment::from_integer(const Option& opt, long long input) {
	if (opt.kind == Kind::BOOLEAN) {
		return { &opt, input, false, input ? "on" : "off", input };
	}

	const auto* choice = opt.find_choice(input);
	if (choice) return from_choice(opt, *choice);
	return { &opt, input, false, "", input };
}

Assignment Assignment::make_reset(const Option& opt) {
	return { &opt, 0, true, "", 0 };
}

Assignment Assignments::parse_assignment(lua_State* L, int index, const Option& opt) {
	auto invalid = [&]() -> Assignment {
		throw std::runtime_error("qalc: invalid value for " + opt.name);
	};

	if (opt.kind == Kind::BOOLEAN || opt.accept_boolean) {
		bool boolean;
		if (read_boolean(L, index, boolean)) return Assignment::from_integer(opt, boolean);
		if (opt.kind == Kind::BOOLEAN) return invalid();
	}

	double number;
	if (lua_type(L, index) == LUA_TSTRING) {
		const auto text = string_at(L, index);
		const auto* choice = opt.find_choice(text);
		if (choice) return Assignment::from_choice(opt, *choice);

		for (unsigned char c : text) {
			if (std::isspace(c) || c == 0) return invalid();
		}

		char* end;
		number = std::strtod(text.c_str(), &end);
		if (end == text.c_str() || *end != '\0') return invalid();
	} else if (lua_type(L, index) == LUA_TNUMBER) {
		number = lua_tonumber(L, index);
	} else {
		return invalid();
	}

	if (!std::isfinite(number) || std::floor(number) != number) return invalid();
	if (opt.kind == Kind::BASE) {
		if (number < 2 || number > 36) return invalid();
	} else if (number < opt.min || number > opt.max) {
		return invalid();
	}

	const auto input = static_cast<long long>(number);
	if (opt.kind == Kind::ENUM && !opt.find_choice(input)) return invalid();
	if (std::find(opt.excluded.begin(), opt.excluded.end(), input)
		!= opt.excluded.end()) return invalid();

	return Assignment::from_integer(opt, input);
}

Assignment Assignments::read_assignment(
	lua_State* L, const std::string& name, int index, bool reset
) {
	const auto key = lower(name);
	for (const auto& shortcut : shortcuts) {
		if (key != shortcut.name
			&& std::find(shortcut.aliases.begin(), shortcut.aliases.end(), key)
				== shortcut.aliases.end()) continue;

		const auto& target = find_opt(shortcut.target);
		if (reset) return Assignment::make_reset(target);
		bool enabled;
		if (!read_boolean(L, index, enabled)) {
			throw std::runtime_error("qalc: invalid value for " + shortcut.name);
		}

		return Assignment::from_integer(target, enabled ? shortcut.on : shortcut.off);
	}

	const auto& opt = find_opt(name);
	if (!reset && lua_type(L, index) == LUA_TSTRING) {
		const auto text = string_at(L, index);
		auto redirect = opt.redirects.find(text);
		if (redirect == opt.redirects.end()) redirect = opt.redirects.find(lower(text));
		if (redirect != opt.redirects.end()) {
			return parse_assignment(L, index, find_opt(redirect->second));
		}
	}

	return reset ? Assignment::make_reset(opt) : parse_assignment(L, index, opt);
}

// }}}

// {{{ assignment collection and receipts
bool Assignment::is_same_value(const Assignment& other) const {
	return reset == other.reset
		&& value == other.value
		&& display_num == other.display_num;
}

void Assignment::push_display(lua_State* L) const {
	if (label.empty()) {
		lua_pushnumber(L, display_num);
	} else {
		lua::push(L, label);
	}
}

void Assignments::insert(const Assignment& assignment) {
	const auto inserted = entries.emplace(assignment.opt->name, assignment);
	if (!inserted.second && !inserted.first->second.is_same_value(assignment)) {
		throw std::runtime_error("qalc: conflicting option " + assignment.opt->name);
	}
}

void Assignments::add(const Assignment& assignment) {
	insert(assignment);
	switch (assignment.opt->coupling) {
	case Coupling::PARSING_MODE:
		insert(Assignment::make_reset(find_opt("rpn_syntax")));
		break;
	case Coupling::SEPARATORS:
		if (!assignment.reset && assignment.value) {
			insert(Assignment::from_integer(find_opt("ignore_dot"), 0));
			insert(Assignment::from_integer(find_opt("decimal_comma"), 0));
		}
		break;
	case Coupling::NONE:
		break;
	}
}

Assignments Assignments::read(lua_State* L, int index, bool reset) {
	if (!lua_istable(L, index)) throw std::runtime_error("qalc: expected a table");
	index = lua::abs_index(L, index);
	const auto length = lua_objlen(L, index);
	Assignments assignments;
	std::size_t count = 0;
	lua_pushnil(L);
	while (lua_next(L, index)) {
		if (reset) {
			const double key = lua_tonumber(L, -2);
			if (lua_type(L, -2) != LUA_TNUMBER || key < 1
				|| key > length || std::floor(key) != key) {
				throw std::runtime_error("qalc: expected an array of option names");
			}
		}

		const auto name = string_at(L, reset ? -1 : -2);
		assignments.add(read_assignment(L, name, -1, reset));
		++count;
		lua_pop(L, 1);
	}

	if (reset && count != length) {
		throw std::runtime_error("qalc: expected an array of option names");
	}

	return assignments;
}

void Assignments::push_receipt(lua_State* L) const {
	lua_newtable(L);
	lua_newtable(L);
	int removed = 0;
	bool reparse = false;
	for (const auto& entry : entries) {
		const auto& assignment = entry.second;
		reparse = reparse || assignment.opt->reparse;
		if (assignment.reset) {
			lua::push(L, entry.first);
			lua_rawseti(L, -2, ++removed);
		} else {
			assignment.push_display(L);
			lua_setfield(L, -3, entry.first.c_str());
		}
	}

	lua_pushboolean(L, reparse);
}

ConfigUpdate Assignments::to_update() const {
	ConfigUpdate update;
	for (const auto& entry : entries) {
		const auto& assignment = entry.second;
		const auto id = static_cast<std::size_t>(assignment.opt - schema().data());
		update.changes.push_back({ id, assignment.value, assignment.reset });
	}

	return update;
}
// }}}

// {{{ lua-facing
static void push_spec(
	lua_State* L, const std::string& name,
	const std::vector<std::string>& aliases, const std::vector<std::string>& values
) {
	lua_createtable(L, 0, 3);
	lua::push_and_set(L, name, "name");
	lua::make_array<std::string>(L, aliases);
	lua_setfield(L, -2, "aliases");

	lua::make_array<std::string>(L, values);
	lua_setfield(L, -2, "values");
}

void ConfigUpdate::apply(Options& options, Calculator* calc) const {
	for (const auto& change : changes) {
		const Option& opt = schema()[change.option_id];
		if (change.reset) opt.binding.reset(options, calc);
		else opt.binding.set(options, calc, change.value);
	}

	options.derive_retained_prefs();
}

// see SeparatorState for more info
SeparatorState ConfigUpdate::updated_seps(SeparatorState state) const {
	for (const auto& change : changes) {
		const auto& name = schema()[change.option_id].name;

		if (name == "decimal_comma") {
			state.decimal_comma = change.reset ? -1 : change.value;
		} else if (name == "ignore_dot") {
			state.ignore_dot = change.reset
				? defaults().parse.dot_as_separator : change.value;
		} else if (name == "ignore_comma") {
			state.ignore_comma = change.reset
				? defaults().parse.comma_as_separator : change.value;
		}
	}

	const bool comma = state.decimal_comma < 0
		? state.startup_decimal_comma
		: state.decimal_comma != 0;

	if ((comma && state.ignore_comma) || (!comma && state.ignore_dot)) {
		throw std::runtime_error(comma
			? "qalc: incompatible separator settings: ignore_comma with decimal comma"
			: "qalc: incompatible separator settings: ignore_dot with decimal point"
		);
	}

	return state;
}

int lua_option_schema(lua_State* L) {
	try {
		lua_createtable(L, schema().size() + shortcuts.size(), 0);
		int index = 1;
		for (const auto& opt : schema()) {
			push_spec(L, opt.name, opt.aliases, opt.candidates());
			lua_rawseti(L, -2, index++);
		}

		for (const auto& shortcut : shortcuts) {
			push_spec(L, shortcut.name, shortcut.aliases,
				{ "0", "1", "false", "off", "on", "true" });
			lua_rawseti(L, -2, index++);
		}

		return 1;
	} catch (const std::exception& error) {
		lua_pushstring(L, error.what());
	}

	return lua_error(L);
}

ConfigUpdate read_option_update(lua_State* L, int index, bool reset) {
	const auto assignments = Assignments::read(L, index, reset);
	auto update = assignments.to_update();
	assignments.push_receipt(L);
	return update;
}
// }}}

}
