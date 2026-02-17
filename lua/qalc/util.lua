local M = {}

M.ns_track = vim.api.nvim_create_namespace('qalc_track')
M.ns_ui = vim.api.nvim_create_namespace('qalc_ui')

M.JobType = {
	DELETE_SYM = 1,
	CLEAR_SYMS = 2,
	PARSE_LINE = 3,
	EVAL_LINE = 4,
	-- GET_DEFS = 5,
}

M.comment_pat = '#.*$'

return M
