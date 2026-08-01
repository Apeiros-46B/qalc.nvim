-- set up connection with the C++ library and handle querying of definitions
local util = require('qalc.util')

local callback_registered = false

local M = {}

-- array[{ type: LspKind, ref_name, input_name, documentation }]
M.QALC_BUILTINS = {}

-- array[string]
M.DYNAMIC_SYNTAX_CMDS = {}

-- ref_name -> { type: LspKind, ref_name, input_name, documentation }
local BUILTIN_LOOKUP = {}

local PREFS = {} -- array[string]
local UNITS = {} -- array[string]

function M.syntax_highlight()
	if M.DYNAMIC_SYNTAX_CMDS then
		for _, cmd in ipairs(M.DYNAMIC_SYNTAX_CMDS) do
			pcall(vim.cmd, cmd)
		end
	end
end

function M.submit(type, bufnr, extmark, payload)
	-- strip comments
	if (type == util.JobType.EVAL_LINE or type == util.JobType.PARSE_LINE) then
		payload = payload:gsub(util.comment_pat, '')
	end

	-- don't allow legacy function syntax, too hard to parse for depgraph
	local is_forbidden = payload:match('^%s*function%s+')
	local is_blank = not payload:match('%S')

	if type == util.JobType.EVAL_LINE then
		if is_forbidden then
			util.emit_signal('diags_ready', bufnr, extmark, {{
				message = 'Legacy "function" syntax disabled. Use f(x) := ...',
				severity = vim.diagnostic.severity.ERROR,
			}})
			return
		elseif is_blank then
			-- clear stale results for blank lines
			util.emit_signal('result_cleared', bufnr, extmark)
			return
		end
	elseif type == util.JobType.PARSE_LINE then
		if is_forbidden or is_blank then
			-- force parser to parse empty string to update depgraph in callback
			-- we can't update it directly because race conditions might occur
			-- sending jobs enforces a strict order since they are queued on the worker thread
			payload = ''
		end
	end

	require('qalc.lib').submit_job(type, bufnr, extmark, payload)
end

local function handle_get_defs(attached_bufs, defs)
	M.QALC_BUILTINS = defs

	-- dynamic syntax highlighting generation
	local co = coroutine.create(function()
		local funcs, consts, units, prefs = {}, {}, UNITS, PREFS
		local extra_isk = {}
		local has_extra_isk = false

		local function process_def_name(def, name)
			if not BUILTIN_LOOKUP[name] then
				BUILTIN_LOOKUP[name] = {}
			end
			BUILTIN_LOOKUP[name][#BUILTIN_LOOKUP[name]+1] = def

			if def.type == util.LspKind.FUNC then
				funcs[#funcs+1] = name
			elseif def.type == util.LspKind.CONST then
				consts[#consts+1] = name
			elseif def.type == util.LspKind.UNIT then
				units[#units+1] = name
			elseif def.type == util.LspKind.ENUM_MB then
				prefs[#prefs+1] = name
			end

			-- iterate over UTF-8 chars for iskeyword generation
			for c in name:gmatch('[%z\1-\127\194-\244][\128-\191]*') do
				-- if the character's byte length > 1, it is a non-ascii unicode char
				if string.len(c) > 1 then
					extra_isk[c] = true
					has_extra_isk = true
				end
			end
		end

		local count = 0
		for _, def in ipairs(defs) do
			for _, name in ipairs(def.all_names or {}) do
				process_def_name(def, name)
			end
			count = count + 1
			-- yield every 500 items so we don't hang the UI
			if count % 100 == 0 then
				coroutine.yield()
			end
		end

		-- sort prefixes by length so "milli" matches before "m"
		table.sort(prefs, function(a, b)
			return #a > #b
		end)

		-- generate iskeyword option (see :h iskeyword)
		local isk_base = '@,48-57,_,$'
		if has_extra_isk then
			isk_base = isk_base .. ',' .. table.concat(vim.tbl_keys(extra_isk), ',')
		end

		M.DYNAMIC_SYNTAX_CMDS = { 'syn iskeyword ' .. isk_base }
		local cmds = M.DYNAMIC_SYNTAX_CMDS

		-- generate regexes
		-- \(\<\|\d\@<=\) = start at a word boundary or immediately after a digit
		-- ("2kg" is matched as 2 being a number and kg being a prefixed unit)
		local function join_regex_names(names)
			local escaped = {}
			for i, name in ipairs(names) do
				escaped[i] = vim.fn.escape(name, '\\.*$^~[]')
			end
			return table.concat(escaped, [[\|]])
		end

		cmds[#cmds+1] = ([[syn match qalcFunction '\(\<\|\d\@<=\)\(%s\)\>']]):format(
			join_regex_names(funcs)
		)
		cmds[#cmds+1] = ([[syn match qalcConstant '\(\<\|\d\@<=\)\(%s\)\>']]):format(
			join_regex_names(consts)
		)
		cmds[#cmds+1] = ([[syn match qalcUnit '\(\<\|\d\@<=\)\(%s\)\?\(%s\)\>']]):format(
			join_regex_names(prefs),
			join_regex_names(units)
		)

		-- retroactively apply new syntax highlighting to any open buffers
		for bufnr, _ in pairs(attached_bufs) do
			vim.api.nvim_buf_call(bufnr, M.syntax_highlight)
		end
	end)

	-- repeatedly schedule steps until the coroutine is dead
	local function step_coroutine()
		if coroutine.status(co) ~= 'dead' then
			local ok, err = coroutine.resume(co)
			if not ok then
				vim.notify(
					'qalc syntax error: ' .. tostring(err),
					vim.log.levels.ERROR
				)
			end
			vim.schedule(step_coroutine)
		end
	end
	step_coroutine()
end

function M.register_callback(attached_bufs)
	if callback_registered then return end
	callback_registered = true

	local lib = require('qalc.lib')

	local function handle_job(
		type,
		bufnr,
		extmark,
		output,
		diags,
		out_syms,
		in_syms,
		defs
	)
		-- buffer might have been closed while C++ was working
		if not vim.api.nvim_buf_is_valid(bufnr) then return end

		if type == util.JobType.EVAL_LINE then
			util.emit_signal('eval_done', bufnr, extmark, output, diags)
		elseif type == util.JobType.PARSE_LINE then
			util.emit_signal('parse_done', bufnr, extmark, out_syms, in_syms)
		elseif type == util.JobType.GET_DEFS then
			handle_get_defs(attached_bufs, defs)
		end
	end

	local dummy = vim.uv.new_timer()
	assert(dummy, 'unable to initialize qalc.nvim: uv timer is nil')
	lib.init_loop(dummy)
	dummy:close()

	lib.set_callback(vim.schedule_wrap(handle_job))
	lib.submit_job(util.JobType.GET_DEFS, 0, 0, '')
end

-- get definitions of a word, which may be a prefix + unit combination
function M.get_global_defs_for_word(word)
	if not BUILTIN_LOOKUP then
		return nil
	end
	if BUILTIN_LOOKUP[word] then
		return BUILTIN_LOOKUP[word]
	end

	-- decompose word into prefix + unit
	for _, pref in ipairs(PREFS) do
		if vim.startswith(word, pref) then
			local unit_part = word:sub(#pref + 1)
			local unit_defs = BUILTIN_LOOKUP[unit_part]

			if unit_defs then
				local pref_defs = BUILTIN_LOOKUP[pref]
				local combined = {}
				for _, p in ipairs(pref_defs) do
					combined[#combined+1] = p
				end
				for _, u in ipairs(unit_defs) do
					combined[#combined+1] = u
				end
				return combined
			end
		end
	end

	return nil
end

-- try to complete the input as a prefix-unit combination
function M.complete_prefix_unit(input, callback)
	if not M.QALC_BUILTINS or #input == 0 then return end

	-- glue prefixes and units together to possibly complete the input
	for _, pref_name in ipairs(PREFS) do
		if vim.startswith(pref_name, input) or vim.startswith(input, pref_name) then
			for _, unit_name in ipairs(UNITS) do
				local combined = pref_name .. unit_name
				if vim.startswith(combined, input) then
					local unit_defs = BUILTIN_LOOKUP[unit_name]
					local doc = unit_defs and unit_defs[1] and unit_defs[1].documentation or ''
					callback(combined, pref_name, unit_name, doc)
				end
			end
		end
	end
end

return M
