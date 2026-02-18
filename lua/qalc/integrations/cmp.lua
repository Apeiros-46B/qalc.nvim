-- cmp integration
-- TODO: I think this has a little more room for optimization
local util = require('qalc.util')

local M = {}
M.__index = M

function M.new()
	local self = setmetatable({}, M)

	self.static_items = nil

	-- for JIT prefix-unit completion
	self.raw_units = {}
	self.raw_prefixes = {}

	return self
end

function M:is_available()
	return vim.bo.filetype == 'qalc'
end

function M:get_debug_name()
	return 'qalc'
end

function M:get_keyword_pattern()
	return [[\k\+]]
end

function M:_add_completion(def, name, documentation)
	local item = {
		label = name,
		insertText = name,
		kind = def.type,
		sortText = '1_' .. name, -- force builtin symbols to sort after local ones
		documentation = documentation,
	}
	self.static_items[#self.static_items+1] = item

	if def.type == util.LspKind.UNIT then
		self.raw_units[#self.raw_units+1] = item
	elseif def.type == util.LspKind.ENUM_MB then
		self.raw_prefixes[#self.raw_prefixes+1] = item
	end
end

function M:complete(request, callback)
	if not self.static_items then
		self.static_items = {}

		for _, def in pairs(require('qalc.bridge').QALC_BUILTINS or {}) do
			-- share one documentation table across many names
			local shared_doc = { kind = 'markdown', value = def.documentation }
			for _, name in ipairs(def.all_names or {}) do
				self:_add_completion(def, name, shared_doc)
			end
		end
	end

	-- shallow copy; this copies table refs, not the entire tables
	local items = {}
	for i = 1, #self.static_items do
		items[i] = self.static_items[i]
	end

	-- JIT generation of prefix-unit combinations
	-- this allows us to avoid filling the table with all prefix-unit combinations
	local input = request.context.cursor_before_line:match('[%a_]+$') or ''
	if #input > 0 then
		for _, pref in ipairs(self.raw_prefixes) do
			if vim.startswith(pref.label, input) or vim.startswith(input, pref.label) then
				for _, unit in ipairs(self.raw_units) do
					local combined_label = pref.label .. unit.label
					if vim.startswith(combined_label, input) then
						items[#items+1] = {
							label = combined_label,
							insertText = combined_label,
							kind = vim.lsp.protocol.CompletionItemKind.Unit,
							sortText = 'z_' .. combined_label, -- sort after everything else
							detail = 'Prefix: ' .. pref.label .. '\n',
							documentation = unit.documentation,
						}
					end
				end
			end
		end
	end

	-- push locals
	local bufnr = request.context.bufnr
	local graph = require('qalc.buffer').attached_bufs[bufnr]
	if graph then
		graph:for_all_symbols(function(def)
			items[#items+1] = {
				label = def.ref_name,
				insertText = def.ref_name,
				kind = def.type,
				detail = 'Local symbol',
				sortText = '0_' .. def.ref_name,
			}
		end)
	end

	callback(items)
end

-- try registering cmp source
function M.register()
	local ok, cmp = pcall(require, 'cmp')
	if ok then
		cmp.register_source('qalc', M.new())
	end
end

return M
