-- extends dest with src (with mutation, unlike vim.tbl_deep_extend 'force')
local function deep_extend(dest, src)
	for k, v in pairs(src) do
		if type(v) ~= 'table' then
			dest[k] = v
		else
			deep_extend(dest[k], v)
		end
	end
end

-- returns a callable table that can be called like t() or t.s() with
-- the s variant providing a nil first argument to the inner function
local function with_nil_variant(f, s)
	return setmetatable(
		{
			[s] = function(...)
				f(nil, ...)
			end
		},
		{
			__call = function(_, ...)
				return f(...)
			end
		}
	)
end

return {
	deep_extend      = deep_extend,
	with_nil_variant = with_nil_variant,
}
