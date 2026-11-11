local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.dirname(vim.fn.fnamemodify(source, ':p'))

local result = vim.system({ 'nix', 'build' }, { cwd = root .. '/lib' }):wait()
if result.code ~= 0 then
	error(result.stderr or result.stdout or 'build command failed')
end

local exts = { 'dll', 'dylib', 'so' }
local src
for _, ext in ipairs(exts) do
	if vim.uv.fs_stat(root .. '/lib/result/lib/libqalcbridge.' .. ext) then
		src = '../../lib/result/lib/libqalcbridge.' .. ext
		break
	end
end
assert(src, 'built qalcbridge library not found')

for _, ext in ipairs(exts) do
	local dst = root .. '/lua/qalc/lib.' .. ext

	vim.uv.fs_unlink(dst)
	vim.uv.fs_symlink(src, dst)
end
