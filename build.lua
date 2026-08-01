local function run(cmd)
	local result = vim.system(cmd):wait()
	if result.code ~= 0 then
		error(result.stderr or result.stdout or 'build command failed')
	end
end

run({
	'cmake',
	'-DCMAKE_BUILD_TYPE=Release',
	'-S', './lib',
	'-B', './lib/build'
})
run({ 'cmake', '--build', './lib/build' })

-- not sure which extension is used, so we just make symlinks for all of them
-- TODO: replace this with `cmake --install`
local exts = { 'dll', 'dylib', 'so' }
for _, ext in ipairs(exts) do
	local src = '../../lib/build/libqalcbridge.' .. ext
	local dst = './lua/qalc/lib.' .. ext

	vim.uv.fs_unlink(dst)
	vim.uv.fs_symlink(src, dst)
end
