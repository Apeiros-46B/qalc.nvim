local M = {}

M.ns_ui = vim.api.nvim_create_namespace('qalc_ui')

M.JobType = {
	PARSE_BATCH = 1,
	EVAL_BATCH = 2,
	GET_DEFS = 3,
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
