local M = {}
local schemas = require('qalc.schema')

local scope_aliases = {
	parse = 'parse_options',
	print = 'print_options',
	eval = 'evaluation_options',
	evaluation = 'evaluation_options',
}

local function canonical_name(val)
	return val:lower():gsub('[%s%-]+', '_')
end

local function invalid(path, val)
	error(('qalc: invalid value for %s: %s'):format(path, vim.inspect(val)), 3)
end

local function bool_val(val)
	if type(val) == 'boolean' then return val end
	if type(val) == 'number' and (val == 0 or val == 1) then
		return val == 1
	end
	if type(val) == 'string' then
		local name = canonical_name(val)
		if name == 'on' or name == 'yes' or name == 'true' or name == '1' then
			return true
		end
		if name == 'off' or name == 'no' or name == 'false' or name == '0' then
			return false
		end
	end
	return nil
end

local function normalize_bool(path, val)
	local res = bool_val(val)
	if res ~= nil then return res end
	invalid(path, val)
end

local function normalize_int(path, spec, val)
	if type(val) == 'string' then
		local named = spec.values and spec.values[canonical_name(val)]
		if named ~= nil then val = named else val = tonumber(val) end
	end

	if type(val) ~= 'number' or val % 1 ~= 0 then invalid(path, val) end
	if spec.min and val < spec.min then invalid(path, val) end
	if spec.max and val > spec.max then invalid(path, val) end

	return val
end

local function normalize_val(path, spec, val)
	if spec.type == 'boolean' then
		val = normalize_bool(path, val)
		return val

	elseif spec.type == 'integer' then
		if spec.allow_boolean then
			local normalized = bool_val(val)
			if normalized ~= nil then return normalized and 1 or 0 end
		end
		return normalize_int(path, spec, val)

	elseif spec.type == 'enum' then
		if spec.allow_boolean and type(val) == 'boolean' then
			return val and 1 or 0
		end
		return normalize_int(path, spec, val)

	elseif spec.type == 'string' then
		if type(val) ~= 'string' then invalid(path, val) end
		return val
	end

	error('qalc: invalid option schema for ' .. path, 3)
end

-- sentinel value for resetting an option to default since nil values aren't
-- distinguishable from a missing kv pair in lua tables
local RESET = {}

local function is_reset(spec, val)
	return val == nil or (val == '' and spec.type ~= 'string')
end

local function normalize_node(path, spec, val)
	if is_reset(spec, val) then return RESET end

	if spec.type ~= 'table' then
		return normalize_val(path, spec, val)
	end

	if type(val) ~= 'table' then invalid(path, val) end

	local normalized = {}

	for k, v in pairs(val) do
		local child = spec.fields[k]
		local child_path = path .. '.' .. k

		if not child then error('qalc: unknown option ' .. child_path, 3) end

		normalized[k] = normalize_node(child_path, child, v)
	end

	return normalized
end

local function without_resets(val)
	if val == RESET then return nil end
	if type(val) ~= 'table' then return val end

	local result = {}

	for k, child in pairs(val) do
		result[k] = without_resets(child)
	end

	return result
end

function M.normalize_cfg(cfg)
	if cfg ~= nil and type(cfg) ~= 'table' then
		error('qalc: config must be a table', 2)
	end

	local normalized = vim.deepcopy(cfg or {})
	local opt_groups = {}

	for group, schema in pairs(schemas) do
		local values = normalized[group]
		normalized[group] = nil

		if values ~= nil then
			if type(values) ~= 'table' then
				error('qalc: ' .. group .. ' must be a table', 2)
			end

			local spec = { type = 'table', fields = schema }
			opt_groups[group] = without_resets(normalize_node(group, spec, values))
		end
	end

	return normalized, opt_groups
end

local function resolve_path(path)
	local parts = vim.split(path, '.', { plain = true })
	local scope = table.remove(parts, 1)
	local group = scope_aliases[scope] or scope
	local fields = schemas[group]

	if not fields or #parts == 0 then return end

	local spec

	for i, key in ipairs(parts) do
		spec = fields[key]

		if not spec then return end

		if i < #parts then
			if spec.type ~= 'table' then return end
			fields = spec.fields
		end
	end

	return { group = group, keys = parts }, spec
end

local function collect_updates(updates, group, keys, val)
	if val ~= RESET and type(val) == 'table' then
		for key, child in pairs(val) do
			local child_keys = vim.list_extend(vim.deepcopy(keys), { key })
			collect_updates(updates, group, child_keys, child)
		end

		return
	end

	local upd = { group = group, keys = keys }

	if val ~= RESET then upd.val = val end

	updates[#updates+1] = upd
end

function M.normalize_cmd(path, val)
	path = canonical_name(path)

	local resolved, spec = resolve_path(path)

	if not resolved then error('qalc: unknown option ' .. path, 2) end

	local full_path = resolved.group .. '.' .. table.concat(resolved.keys, '.')
	local normalized = normalize_node(full_path, spec, val)
	local updates = {}

	collect_updates(updates, resolved.group, resolved.keys, normalized)

	return updates
end

local function collect_paths(paths, prefix, fields)
	for key, spec in pairs(fields) do
		local path = prefix .. '.' .. key

		if spec.type == 'table' then
			collect_paths(paths, path, spec.fields)
		else
			paths[#paths+1] = path
		end
	end
end

local cached_paths
local cached_values = {}

local function option_paths()
	if not cached_paths then
		cached_paths = {}

		for group, schema in pairs(schemas) do
			collect_paths(cached_paths, group:gsub('_options$', ''), schema)
		end

		table.sort(cached_paths)
	end

	return cached_paths
end

function M.option_paths()
	return vim.deepcopy(option_paths())
end

local function option_values(spec)
	if cached_values[spec] then return cached_values[spec] end

	local values = {}
	local seen = {}

	local function add(value)
		value = tostring(value)

		if not seen[value] then
			seen[value] = true
			values[#values+1] = value
		end
	end

	for name in pairs(spec.values or {}) do add(name) end

	if spec.type == 'enum' then
		for value = spec.min, spec.max do add(value) end
	elseif spec.type == 'boolean' or spec.allow_boolean then
		for _, value in ipairs({ 'on', 'off', 'true', 'false', '0', '1' }) do
			add(value)
		end
	end

	table.sort(values)
	cached_values[spec] = values

	return values
end

-- sorted candidates allow direct skip to first possible match
local function prefix_matches(candidates, prefix)
	local first, last = 1, #candidates + 1

	while first < last do
		local middle = math.floor((first + last) / 2)

		if candidates[middle] < prefix then
			first = middle + 1
		else
			last = middle
		end
	end

	local matches = {}

	for i = first, #candidates do
		local value = candidates[i]

		if value:sub(1, #prefix) ~= prefix then break end

		matches[#matches+1] = value
	end

	return matches
end

function M.complete(arglead, cmdline, cursorpos)
	local before_cursor = cmdline:sub(1, cursorpos)
	local args = before_cursor:match('QalcSet%s+(.*)$')

	if not args then return {} end

	local path, value = args:match('^(%S+)%s+(.*)$')

	if not path then
		return prefix_matches(option_paths(), canonical_name(arglead))
	end

	-- values with spaces may be entered manually but have no schema candidates
	if value:find('%s') then return {} end

	local _, spec = resolve_path(canonical_name(path))

	if not spec then return {} end

	return prefix_matches(option_values(spec), canonical_name(arglead))
end

return M
