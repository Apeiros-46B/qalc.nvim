-- show hover documentation
local cfg = require('qalc.config').cfg
local util = require('qalc.util')

local M = {}

function M.show(bufnr)
	bufnr = bufnr or vim.api.nvim_get_current_buf()
	-- iskeyword handles this properly
	local raw_word = vim.fn.expand('<cword>')
	-- remove leading numbers so 2kg -> kg
	local word = raw_word:gsub('^[%d%.]+', '')

	if word == '' then return end

	local lines = {}

	local graph = require('qalc.buffer').attached_bufs[bufnr]
	if graph and graph.extmarks and graph.extmarks[word] then
		-- local symbol lookup
		local extmark_id = graph.extmarks[word]
		lines[#lines+1] = '**' .. word .. ':** Local Symbol'

		local pos = vim.api.nvim_buf_get_extmark_by_id(bufnr, util.ns_track, extmark_id, {})
		if pos and pos[1] then
			local lnum = pos[1]
			local line_text = vim.api.nvim_buf_get_lines(bufnr, lnum, lnum + 1, false)[1]
			if line_text then
				lines[#lines+1] = '**Definition:** `' .. vim.trim(line_text) .. '`'
			end
		end
	else
		-- fallback to globals
		local defs = require('qalc.bridge').get_global_defs_for_word(word)
		if not defs or #defs == 0 then
			vim.notify('qalc: No documentation found for: ' .. word, vim.log.levels.INFO)
			return
		end

		for i, def in ipairs(defs) do
			for line in def.documentation:gmatch("([^\n]*)\n?") do
				if line ~= '' then
					lines[#lines+1] = line
				end
			end
			if i < #defs then
				lines[#lines+1] = ''
				lines[#lines+1] = '---'
				lines[#lines+1] = ''
			end
		end
	end

	vim.lsp.util.open_floating_preview(lines, 'markdown', cfg.display.hover)
end

function M.bind_key(bufnr)
	vim.keymap.set('n', 'K', M.show, {
		buffer = bufnr,
		desc = 'Show hover documentation for the current symbol'
	})
end

return M
