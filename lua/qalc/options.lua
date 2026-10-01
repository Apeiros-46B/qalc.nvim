-- this is ai generated
local M = {}
local schema = require('qalc.schema')

local aliases = {}
for key, spec in pairs(schema) do
	aliases[spec.name] = key
	for _, alias in ipairs(spec.aliases) do
		aliases[alias] = key
	end
end

local function invalid(name, value)
	error(('qalc: invalid value for %s: %s'):format(name, vim.inspect(value)), 3)
end

local function boolean(name, value)
	if type(value) == 'boolean' then return value end
	if value == 1 or value == 0 then return value == 1 end

	if type(value) == 'string' then
		local v = value:lower()

		if v == 'on' or v == 'yes' or v == 'true' or v == '1' then
			return true
		end

		if v == 'off' or v == 'no' or v == 'false' or v == '0' then
			return false
		end
	end

	invalid(name, value)
end

local function normalize(key, value)
	local spec = schema[key]

	if value == nil or value == '' then return nil end

	if type(value) == 'string' and value:find('%s') then
		invalid(spec.name, value)
	end

	if spec.type == 'boolean' then
		return boolean(spec.name, value)
	end

	local number
	if type(value) == 'string' then
		-- preserve E/e which have different meanings
		number = spec.values[value] or spec.values[value:lower()]
	end

	if number ~= nil then return number end

	number = tonumber(value)
	if not number or number % 1 ~= 0 then
		invalid(spec.name, value)
	end

	if spec.type == 'enum' then
		if spec.numeric[number] == nil then
			invalid(spec.name, value)
		end

		return spec.numeric[number]
	end

	if spec.type == 'base' then
		if number < 2 or number > 36 then
			invalid(spec.name, value)
		end
	elseif (spec.min and number < spec.min) or (spec.max and number > spec.max)
		or (key == 'binary_bits' and number == 1)
	then
		invalid(spec.name, value)
	end

	return number
end

function M.change(current, name, value)
	if type(name) ~= 'string' then
		error('qalc: option name must be a string', 2)
	end

	local key = aliases[name:lower()]
	if not key then
		error('qalc: unknown option ' .. name, 2)
	end

	local result = vim.deepcopy(current)
	local v = normalize(key, value)

	if key == 'exact' then
		key = 'approximation'
		if v ~= nil then
			v = v and 0 or 1
		end
	elseif key == 'round_to_even' then
		key = 'rounding'
		if v ~= nil then
			v = v and 1 or 0
		end
	elseif key == 'lowercase_e' then
		key = 'exp_display'
		if v ~= nil then
			v = v and 2 or 1
		end
	end

	result[key] = v

	if key == 'parsing_mode' then
		result.rpn_syntax = nil
	end

	if key == 'ignore_comma' and v then
		result.ignore_dot = false
		result.decimal_comma = 0
	end

	return result
end

function M.normalize_cfg(cfg)
	if cfg ~= nil and type(cfg) ~= 'table' then
		error('qalc: config must be a table', 2)
	end

	local normalized = vim.deepcopy(cfg or {})
	local values = normalized.options
	normalized.options = nil

	if values == nil then return normalized end
	if type(values) ~= 'table' then
		error('qalc: options must be a table', 2)
	end

	local result, assigned = {}, {}

	-- stable setup ordering, reject conflicting aliases
	for _, name in ipairs(vim.fn.sort(vim.tbl_keys(values))) do
		local changed = M.change(result, name, values[name])

		for key, value in pairs(changed) do
			if not vim.deep_equal(value, result[key]) then
				if assigned[key] then
					error('qalc: conflicting option ' .. schema[key].name, 2)
				end

				assigned[key] = true
			end
		end

		result = changed
	end

	return normalized, result
end

-- translate high-level opts to the native configuration job payload
function M.snapshot(values)
	local result = {}

	for key, value in pairs(values) do
		for _, native in ipairs(schema[key].keys) do
			if native == 'evaluation.assume_denominators_nonzero' then
				value = value and 1 or 0
			end

			result[native] = value
		end
	end

	for _, kind in ipairs({ 'min', 'max' }) do
		local v = values[kind .. '_decimals']

		if v ~= nil then
			result['print.use_' .. kind .. '_decimals'] = v >= 0

			if v >= 0 or kind == 'min' then
				result['print.' .. kind .. '_decimals'] = math.max(0, v)
			end
		end
	end

	if values.unicode ~= nil or values.unicode_exponents ~= nil then
		local exponents = values.unicode_exponents or 1

		result['print.use_unicode_signs'] = values.unicode == false and 0
			or ({ [0] = 3, 1, 2 })[exponents]
	end

	if values.approximation ~= nil then
		local v = values.approximation

		result['evaluation.approximation'] = (v < 0 or v == 3) and 1 or v
		result['output.auto_approximation'] = v < 0 and 2 or (v == 3 and 3 or 0)
	end

	if values.fractions ~= nil then
		local v = values.fractions

		result['print.number_fraction_format'] = (v < 0 or v == 10) and 0 or (v == 9 and 2 or v)
		result['print.restrict_fraction_length'] = v == 2 or v == 3
		result['output.auto_fraction'] = v < 0 and 2 or (v == 10 and 3 or 0)
	end

	if values.algebra_mode ~= nil then
		result['evaluation.structuring'] = values.algebra_mode
		result['print.allow_factorization'] = values.algebra_mode == 2
	end

	if values.autoconversion ~= nil then
		result['evaluation.auto_post_conversion'] = ({ [0] = 0, 3, 2, 1, 0 })[values.autoconversion]
		result['evaluation.mixed_units_conversion'] = values.autoconversion == 0 and 0 or 3
	end

	if values.interval_display ~= nil then
		-- The CLI's adaptive mode starts with significant-digit display.
		result['print.interval_display'] = math.max(0, values.interval_display - 1)
	end

	if values.rpn_syntax then
		result['parse.parsing_mode'] = 4
	end

	return result
end

function M.requires_reparse(before, after)
	for _, values in ipairs({ before, after }) do
		for key, _ in pairs(values) do
			if key:match('^parse%.') or key:match('^state%.assumptions%.')
				or key == 'state.decimal_comma' or key == 'state.concise_uncertainty'
			then
				if not vim.deep_equal(before[key], after[key]) then
					return true
				end
			end
		end
	end

	return false
end

local function names()
	local result = {}

	for _, spec in pairs(schema) do
		result[#result+1] = spec.name

		for _, alias in ipairs(spec.aliases) do
			result[#result+1] = alias
		end
	end

	table.sort(result)

	return result
end

function M.option_paths()
	return names()
end

local function candidates(spec)
	local result = {}

	for value in pairs(spec.values) do
		result[#result+1] = value
	end

	for value in pairs(spec.numeric or {}) do
		result[#result+1] = tostring(value)
	end

	if spec.type == 'boolean' then
		vim.list_extend(result, { 'on', 'off', 'true', 'false', '0', '1' })
	end

	table.sort(result)

	return result
end

function M.complete(arglead, cmdline, cursorpos)
	local args = cmdline:sub(1, cursorpos):match('QalcSet%s+(.*)$')
	if not args then return {} end

	local words = vim.split(args, '%s+')
	local choices

	if #words == 1 then
		choices = names()
		arglead = arglead:lower()
	elseif #words == 2 and aliases[words[1]:lower()] then
		choices = candidates(schema[aliases[words[1]:lower()]])
	else
		return {}
	end

	return vim.tbl_filter(function(value)
		return value:sub(1, #arglead) == arglead
	end, choices)
end

function M.describe(values)
	local result = {}

	for key, value in pairs(values) do
		local spec = schema[key]

		if spec.type == 'boolean' then
			value = value and 'on' or 'off'
		else
			for _, label in ipairs(candidates(spec)) do
				if spec.values[label] == value then
					value = label
					break
				end
			end
		end

		result[spec.name] = value
	end

	return result
end

return M
