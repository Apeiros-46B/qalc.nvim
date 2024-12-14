vim.system({
	'cmake',
	'-DCMAKE_BUILD_TYPE=Release',
	'-S', './lib',
	'-B', './lib/build'
}):wait()
vim.system({ 'cmake', '--build', './lib/build' }):wait()

-- not sure which extension is used, so we just make symlinks for all of them
local exts = { 'dll', 'dylib', 'so' }
for _, ext in ipairs(exts) do
	local src = '../../lib/build/libqalcbridge.' .. ext
	local dst = './lua/qalc/lib.' .. ext

	vim.uv.fs_unlink(dst)
	vim.uv.fs_symlink(src, dst)
end
