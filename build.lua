local source = debug.getinfo(1, 'S').source:sub(2)
local root = vim.fs.dirname(vim.fn.fnamemodify(source, ':p'))

local function run(cmd)
	local result = vim.system(cmd, { cwd = root }):wait()
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

-- TODO: replace this with `cmake --install`
local exts = { 'dll', 'dylib', 'so' }
local src
for _, ext in ipairs(exts) do
	if vim.uv.fs_stat(root .. '/lib/build/libqalcbridge.' .. ext) then
		src = '../../lib/build/libqalcbridge.' .. ext
		break
	end
end
assert(src, 'built qalcbridge library not found')

for _, ext in ipairs(exts) do
	local dst = root .. '/lua/qalc/lib.' .. ext

	vim.uv.fs_unlink(dst)
	vim.uv.fs_symlink(src, dst)
end
