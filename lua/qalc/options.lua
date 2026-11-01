-- handle qalc option setting
local lib = require('qalc.lib')
local M = {}

local available_names, available_values = {}, {}

-- read supported options once at module init
for _, option in ipairs(lib.option_schema()) do
	available_names[#available_names+1] = option.name
	available_values[option.name] = option.values

	for _, alias in ipairs(option.aliases) do
		available_names[#available_names+1] = alias
		available_values[alias] = option.values
	end
end

table.sort(available_names)

-- only for display in :QalcSet
local overrides = {}

local function accept(values, removed, reparse)
	for name, value in pairs(values) do
		overrides[name] = value
	end

	for _, name in ipairs(removed) do
		overrides[name] = nil
	end

	return (next(values) ~= nil or #removed > 0), reparse
end

function M.set(values)
	return accept(lib.set_options(values))
end

function M.reset(names)
	return accept(lib.reset_options(names))
end

function M.describe()
	return vim.deepcopy(overrides)
end

function M.option_paths()
	return vim.list_slice(available_names)
end

function M.complete(arglead, cmdline, cursorpos)
	local args = cmdline:sub(1, cursorpos):match('QalcSet%s+(.*)$')
	if not args then return {} end

	local words = vim.split(args, '%s+')
	local choices

	if #words == 1 then
		choices = available_names
		arglead = arglead:lower()
	elseif #words == 2 then
		choices = available_values[words[1]:lower()]
	end

	if not choices then return {} end

	return vim.tbl_filter(function(value)
		return value:sub(1, #arglead) == arglead
	end, choices)
end

return M
