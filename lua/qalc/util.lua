local M = {}

M.ns_track = vim.api.nvim_create_namespace('qalc_track')
M.ns_ui = vim.api.nvim_create_namespace('qalc_ui')

M.JobType = {
	DELETE_SYM = 1,
	CLEAR_SYMS = 2,
	PARSE_LINE = 3,
	EVAL_LINE = 4,
	GET_DEFS = 5,
	ABORT = 6,
}

M.LspKind = {
	FUNC = vim.lsp.protocol.CompletionItemKind.Function,
	VAR = vim.lsp.protocol.CompletionItemKind.Variable,
	UNIT = vim.lsp.protocol.CompletionItemKind.Unit,
	ENUM_MB = vim.lsp.protocol.CompletionItemKind.EnumMember,
	CONST = vim.lsp.protocol.CompletionItemKind.Constant,
}

M.comment_pat = '#.*$'

return M
