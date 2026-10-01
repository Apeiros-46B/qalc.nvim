-- this is ai generated i really did not want to write this myself
local schema = {}

local function option(name, kind, aliases, keys, values, numeric)
	local spec = {
		name = name,
		type = kind,
		aliases = aliases or {},
		keys = keys or {},
		values = values or {},
		numeric = numeric,
	}

	schema[spec.name] = spec

	return spec
end

local function boolean(name, aliases, key)
	return option(name, 'boolean', aliases, { key })
end

local function enum(name, aliases, key, values, numeric)
	return option(name, 'enum', aliases, { key }, values, numeric)
end

local bases = {
	bin = 2, binary = 2, oct = 8, octal = 8, dec = 10, decimal = 10,
	duo = 12, duodecimal = 12, hex = 16, hexadecimal = 16,
	roman = -1, time = -2, unicode = -4, golden = -5, golden_ratio = -5,
	['φ'] = -5, supergolden = -6, supergolden_ratio = -6, ['ψ'] = -6,
	pi = -7, ['π'] = -7, e = -8, sqrt2 = -9, ['sqrt(2)'] = -9, ['√2'] = -9,
	bcd = -20, bijective = -26, b26 = -26,
	fp16 = -30, binary16 = -30, fp32 = -31, binary32 = -31, float = -31,
	fp64 = -32, binary64 = -32, double = -32, fp128 = -33, binary128 = -33, fp80 = -34,
	sexa = 60, sexagesimal = 60, sexa2 = 62, sexagesimal2 = 62, sexa3 = 63, sexagesimal3 = 63,
	latitude = 70, latitude2 = 71, longitude = 72, longitude2 = 73,
}

option('output_base', 'base', { 'base', 'outbase' }, { 'print.base' }, bases)

local input_bases = {}
for k, v in pairs(bases) do
	if v == -1 or v == -4 or (v >= -9 and v <= -5)
		or v == -20 or v == -26 or (v >= 2 and v <= 36)
	then
		input_bases[k] = v
	end
end

option('input_base', 'base', { 'inbase' }, { 'parse.base' }, input_bases)

enum('angle_unit', { 'angle' }, 'parse.angle_unit', {
	none = 0, rad = 1, radians = 1, deg = 2, degrees = 2, gra = 3, gradians = 3,
}, { [0] = 0, 1, 2, 3 })
enum('parsing_mode', { 'parse', 'syntax' }, 'parse.parsing_mode', {
	adaptive = 0, implicit_first = 1, conventional = 2, chain = 3, rpn = 4,
}, { [0] = 0, 1, 2, 3, 4 })
enum('read_precision', { 'readprec' }, 'parse.read_precision', {
	off = 0, always = 1, when_decimals = 2, on = 2,
}, { [0] = 0, 1, 2 })
boolean('units', { 'unit' }, 'parse.units_enabled')
boolean('variables', { 'var' }, 'parse.variables_enabled')
boolean('functions', { 'func' }, 'parse.functions_enabled')
boolean('ignore_dot', { 'nodot' }, 'parse.dot_as_separator')
boolean('ignore_comma', { 'nocomma' }, 'parse.comma_as_separator')
boolean('twos_complement_input', { 'twos_input', 'twosin' }, 'parse.twos_complement')
boolean('hexadecimal_twos_input', { 'hextwosin' }, 'parse.hexadecimal_twos_complement')
local bits = option('binary_bits', 'integer', { 'bits' }, { 'parse.binary_bits', 'print.binary_bits' })
bits.min, bits.max, bits.values = 0, 4294967295, { auto = 0 }

boolean('abbreviations', { 'abbr', 'abbrev' }, 'print.abbreviate_names')
boolean('all_prefixes', { 'allpref' }, 'print.use_all_prefixes')
boolean('prefixes', { 'pref', 'prefix' }, 'print.use_unit_prefixes')
boolean('denominator_prefixes', { 'denpref' }, 'print.use_denominator_prefix')
boolean('place_units_separately', { 'unitsep' }, 'print.place_units_separately')
boolean('excessive_parentheses', { 'expar' }, 'print.excessive_parenthesis')
boolean('show_negative_exponents', { 'negexp' }, 'print.negative_exponents')
boolean('minus_last', { 'minlast' }, 'print.sort_options.minus_last')
boolean('short_multiplication', { 'shortmul' }, 'print.short_multiplication')
boolean('lowercase_numbers', { 'lownum' }, 'print.lower_case_numbers')
boolean('duodecimal_symbols', { 'duosyms' }, 'print.duodecimal_symbols')
boolean('twos_complement', { 'twos' }, 'print.twos_complement')
boolean('hexadecimal_twos', { 'hextwos' }, 'print.hexadecimal_twos_complement')
boolean('spell_out_logical', { 'spellout' }, 'print.spell_out_logical_operators')
boolean('spacious', { 'space' }, 'print.spacious')
boolean('show_ending_zeroes', { 'zeroes' }, 'print.show_ending_zeroes')
boolean('repeating_decimals', { 'repeating_decimal', 'repdeci' }, 'print.indicate_infinite_series')
boolean('unicode', { 'uni' }, 'print.use_unicode_signs')
enum('unicode_exponents', { 'uniexp' }, nil, { off = 0, on = 1, units = 2 }, { [0] = 0, 1, 2 })
enum('base_display', { 'basedisp' }, 'print.base_display', {
	none = 0, normal = 1, alternative = 2,
}, { [0] = 0, 1, 2 })
enum('digit_grouping', { 'group' }, 'print.digit_grouping', {
	off = 0, none = 0, standard = 1, on = 1, locale = 2,
}, { [0] = 0, 1, 2 })
enum('multiplication_sign', { 'mulsign' }, 'print.multiplication_sign', {
	['*'] = 0, ['.'] = 1, ['⋅'] = 1, x = 2, ['×'] = 2, ['·'] = 3,
}, { [0] = 0, 1, 2, 3 })
enum('division_sign', { 'divsign' }, 'print.division_sign', {
	['/'] = 0, ['⁄'] = 1, ['÷'] = 2,
}, { [0] = 0, 1, 2 })
enum('rounding', { 'round' }, 'print.rounding', {
	standard = 0, half_away_from_zero = 0, even = 1, round_to_even = 1,
	half_to_even = 1, half_to_odd = 2, half_toward_zero = 3,
	half_up = 4, half_down = 5, half_random = 6, truncate = 7,
	toward_zero = 7, away_from_zero = 8, up = 9, down = 10,
}, { [0] = 0, 1, 7, 2, 3, 4, 5, 6, 8, 9, 10 })
local scientific = option('scientific_notation', 'integer', { 'exp', 'exp_mode' }, { 'print.min_exp' }, {
	off = 0, auto = -1, pure = 1, scientific = 3, sci = 3, engineering = -3, eng = -3,
})
scientific.min, scientific.max = -2147483648, 2147483647
enum('exp_display', { 'edisp' }, 'print.exp_display', {
	E = 1, e = 2, ['10'] = 3, pow = 3, pow10 = 3, power = 3, power_of_10 = 3,
}, { [0] = 1, 2, 3 })
for _, name in ipairs({ 'min_decimals', 'max_decimals' }) do
	local spec = option(name, 'integer', { name == 'min_decimals' and 'mindeci' or 'maxdeci' }, {}, { off = -1 })
	spec.min, spec.max = -1, 2147483647
end
enum('fractions', { 'fr' }, nil, {
	auto = -1, off = 0, exact = 1, on = 2, combined = 3, mixed = 3, long = 9, dual = 10,
	percent = 6, ['%'] = 6, permille = 7, ['‰'] = 7, permyriad = 8, ['‱'] = 8,
}, { [-1] = -1, [0] = 0, 1, 2, 3, 9, 10, 4, 5, 6, 7, 8 })
enum('interval_display', { 'ivdisp' }, nil, {
	adaptive = 0, significant = 1, interval = 2, plusminus = 3,
	midpoint = 4, lower = 5, upper = 6, concise = 7, relative = 8,
}, { [0] = 0, 1, 2, 3, 4, 5, 6, 7, 8 })

enum('approximation', { 'appr', 'approx' }, nil, {
	auto = -1, exact = 0, try_exact = 1, try = 1, approximate = 2, approx = 2, dual = 3,
}, { [-1] = -1, [0] = 0, 1, 2, 3 })
enum('algebra_mode', { 'alg' }, nil, {
	none = 0, simplify = 1, expand = 1, factorize = 2, factor = 2,
}, { [0] = 0, 1, 2 })
enum('autoconversion', { 'conv' }, nil, {
	none = 0, optimal = 1, base = 2, best = 3, optimalsi = 3, si = 3, mixed = 4,
}, { [0] = 0, 1, 2, 3, 4 })
enum('interval_calculation', { 'ic', 'uncertainty_propagation', 'up' }, 'evaluation.interval_calculation', {
	none = 0, variance_formula = 1, variance = 1, interval_arithmetic = 2, iv = 2,
}, { [0] = 0, 1, 2, 3 })
enum('complex_form', { 'cplxform' }, 'evaluation.complex_number_form', {
	rectangular = 0, cartesian = 0, rect = 0, exponential = 1, exp = 1, polar = 2, cis = 3,
}, { [0] = 0, 1, 2, 3 })
boolean('complex_numbers', { 'cplx' }, 'evaluation.allow_complex')
boolean('infinite_numbers', { 'inf' }, 'evaluation.allow_infinite')
boolean('assume_nonzero_denominators', { 'nzd' }, 'evaluation.assume_denominators_nonzero')
boolean('warn_nonzero_denominators', { 'warnnzd' }, 'evaluation.warn_about_denominators_assumed_nonzero')
boolean('calculate_variables', { 'calcvar' }, 'evaluation.calculate_variables')
boolean('calculate_functions', { 'calcfunc' }, 'evaluation.calculate_functions')
boolean('sync_units', { 'sync' }, 'evaluation.sync_units')
boolean('currency_conversion', { 'curconv' }, 'evaluation.local_currency_conversion')

local precision = option('precision', 'integer', { 'prec' }, { 'state.precision' })
precision.min, precision.max = 1, 2147483647
enum('assumption_type', {}, 'state.assumptions.type', {
	number = 2, num = 2, complex = 2, cplx = 2, real = 4, rational = 5, rat = 5,
	integer = 6, int = 6, boolean = 7, bool = 7,
}, { [2] = 2, [4] = 4, [5] = 5, [6] = 6, [7] = 7 })
enum('assumption_sign', {}, 'state.assumptions.sign', {
	unknown = 0, none = 0, positive = 1, pos = 1, non_negative = 2, nneg = 2,
	negative = 3, neg = 3, non_positive = 4, npos = 4, non_zero = 5, nz = 5,
}, { [0] = 0, 1, 2, 3, 4, 5 })
boolean('interval_arithmetic', { 'ia', 'interval' }, 'state.interval_arithmetic')
boolean('binary_prefixes', { 'binpref' }, 'state.binary_prefixes')
boolean('variable_units', { 'varunits' }, 'state.variable_units')
boolean('concise_uncertainty', { 'concise' }, 'state.concise_uncertainty')
enum('temperature_calculation', { 'temp' }, 'state.temperature_calculation', {
	hybrid = 0, absolute = 1, relative = 2,
}, { [0] = 0, 1, 2 })
enum('sinc', {}, 'state.sinc', { unnormalized = 0, normalized = 1 }, { [0] = 0, 1 })
enum('decimal_comma', {}, 'state.decimal_comma', { locale = -1, off = 0, on = 1 }, { [-1] = -1, [0] = 0, 1 })
-- These CLI shortcuts update their corresponding canonical controls.
option('exact', 'boolean')
option('round_to_even', 'boolean', { 'rndeven' })
option('lowercase_e', 'boolean', { 'lowe' })
option('rpn_syntax', 'boolean', { 'rpnsyn' })
return schema
