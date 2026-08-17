local M = {}

M.ns_ui = vim.api.nvim_create_namespace('qalc_ui')

M.JobType = {
	DELETE_SYM = 1,
	CLEAR_SYMS = 2,
	PARSE_BATCH = 3,
	EVAL_LINE = 4,
	GET_DEFS = 5,
}

M.LspKind = {
	FUNC = vim.lsp.protocol.CompletionItemKind.Function,
	VAR = vim.lsp.protocol.CompletionItemKind.Variable,
	UNIT = vim.lsp.protocol.CompletionItemKind.Unit,
	ENUM_MB = vim.lsp.protocol.CompletionItemKind.EnumMember,
	CONST = vim.lsp.protocol.CompletionItemKind.Constant,
}

M.comment_pat = '#.*$'

-- events:
-- 'eval_done',        (bufnr, stmt_id, output, diagnostics)
-- 'parse_batch_done', (bufnr, req_id, results)

local signal_handlers = {}
local signal_guards = {}

function M.connect_signal(evt, cb)
	signal_handlers[evt] = signal_handlers[evt] or {}
	signal_handlers[evt][#signal_handlers[evt]+1] = cb
end

function M.guard_signal(evt, pred)
	signal_guards[evt] = signal_guards[evt] or {}
	signal_guards[evt][#signal_guards[evt]+1] = pred
end

function M.emit_signal(evt, ...)
	if signal_guards[evt] then
		for _, pred in ipairs(signal_guards[evt]) do
			if not pred(...) then return end
		end
	end

	if signal_handlers[evt] then
		for _, cb in ipairs(signal_handlers[evt]) do
			cb(...)
		end
	end
end

return M
