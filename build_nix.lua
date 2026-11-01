local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.dirname(vim.fn.fnamemodify(source, ':p'))

local result = vim.system({ 'nix', 'build' }, { cwd = root .. '/lib' }):wait()
if result.code ~= 0 then
	error(result.stderr or result.stdout or 'build command failed')
end

-- not sure which extension is used, so we just make symlinks for all of them
local exts = { 'dll', 'dylib', 'so' }
for _, ext in ipairs(exts) do
	local src = '../../lib/result/lib/libqalcbridge.' .. ext
	local dst = root .. '/lua/qalc/lib.' .. ext

	vim.uv.fs_unlink(dst)
	vim.uv.fs_symlink(src, dst)
end
