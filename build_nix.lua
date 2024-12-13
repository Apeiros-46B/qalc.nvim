vim.system({ 'bash', '-c', 'cd lib && nix build' }):wait()

local ext
if vim.fn.has('mac') ~= 0 then
	ext = 'dylib'
else
	ext = 'so'
end

-- TODO: not sure how nix works on mac
local src = '../../lib/result/lib/libqalcbridge.' .. ext
local dst = './lua/qalc/lib.' .. ext

vim.uv.fs_unlink(dst)
vim.uv.fs_symlink(src, dst)
