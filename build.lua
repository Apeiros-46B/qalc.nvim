vim.system({
	'cmake',
	'-DCMAKE_BUILD_TYPE=Release',
	'-S', './lib',
	'-B', './lib/build'
}):wait()
vim.system({ 'cmake', '--build', './lib/build' }):wait()

local ext
if vim.fn.has('win32') ~= 0 then
	ext = 'dll'
elseif vim.fn.has('mac') ~= 0 then
	ext = 'dylib'
else
	ext = 'so'
end

local src = '../../lib/build/libqalcbridge.' .. ext
local dst = './lua/qalc/lib.' .. ext

vim.uv.fs_unlink(dst)
vim.uv.fs_symlink(src, dst)
