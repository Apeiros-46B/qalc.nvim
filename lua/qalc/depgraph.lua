local Graph = {}
Graph.__index = Graph

local M = {}

local function dup_diags(syms)
	local diags = {}

	for _, sym in ipairs(syms) do
		diags[#diags+1] = {
			message = 'Duplicate definition: "' .. sym .. '" is already defined.',
			severity = vim.diagnostic.severity.ERROR,
		}
	end

	return diags
end

local function cycle_diag()
	return {{
		message = 'Reference cycle found here or in dependents, cannot evaluate',
		severity = vim.diagnostic.severity.ERROR,
	}}
end

local function maps_equal(left, right)
	for key, value in pairs(left or {}) do
		if not right or right[key] ~= value then return false end
	end
	for key, value in pairs(right or {}) do
		if not left or left[key] ~= value then return false end
	end
	return true
end

function M.build(stmts)
	local graph = setmetatable({
		nodes = {},
		owners = {},
		dependencies = {},
		dependents = {},
		providers = {},
		dup_diags = {},
		cycle_diags = {},
		blocked = {},
		ord = {},
		stmt_ord = {},
	}, Graph)

	for _, stmt in ipairs(stmts) do
		local parsed = stmt.parsed
		if parsed and not parsed.skip then
			local node = {
				stmt = stmt,
				decl_outputs = parsed.out_syms or {},
				outputs = {},
				in_syms = {},
				norm_expr = parsed.norm_expr,
			}
			local dup_syms = {}
			local seen_out_syms = {}

			for _, def in ipairs(node.decl_outputs) do
				local sym = def.ref_name
				if not seen_out_syms[sym] then
					seen_out_syms[sym] = true
					if graph.owners[sym] then
						dup_syms[#dup_syms+1] = sym
					end
				end
			end

			if #dup_syms == 0 then
				node.outputs = node.decl_outputs
				for _, def in ipairs(node.outputs) do
					graph.owners[def.ref_name] = stmt.id
				end
			else
				graph.dup_diags[stmt.id] = dup_diags(
					dup_syms
				)
			end

			graph.nodes[stmt.id] = node
			graph.dependencies[stmt.id] = {}
			graph.dependents[stmt.id] = {}
			graph.providers[stmt.id] = {}
			graph.stmt_ord[#graph.stmt_ord+1] = stmt.id
		end
	end

	for _, id in ipairs(graph.stmt_ord) do
		local node = graph.nodes[id]
		local own_symbols = {}
		local seen_in_syms = {}

		for _, def in ipairs(node.decl_outputs) do
			own_symbols[def.ref_name] = true
		end

		for _, sym in ipairs(node.stmt.parsed.in_syms or {}) do
			if not own_symbols[sym] and not seen_in_syms[sym] then
				seen_in_syms[sym] = true
				node.in_syms[#node.in_syms+1] = sym

				local provider = graph.owners[sym]
				graph.providers[id][sym] = provider or false
				if provider and provider ~= id and not graph.dependencies[id][provider] then
					graph.dependencies[id][provider] = true
					graph.dependents[provider][#graph.dependents[provider]+1] = id
				end
			end
		end
	end

	local in_deg = {}
	local ready = {}

	for _, id in ipairs(graph.stmt_ord) do
		local count = 0
		for _ in pairs(graph.dependencies[id]) do
			count = count + 1
		end
		in_deg[id] = count
		if count == 0 then
			ready[#ready+1] = id
		end
	end

	local head = 1
	while head <= #ready do
		local id = ready[head]
		head = head + 1
		graph.ord[#graph.ord+1] = id

		for _, dependent in ipairs(graph.dependents[id]) do
			in_deg[dependent] = in_deg[dependent] - 1
			if in_deg[dependent] == 0 then
				ready[#ready+1] = dependent
			end
		end
	end

	if #graph.ord < #graph.stmt_ord then
		for _, id in ipairs(graph.stmt_ord) do
			if in_deg[id] > 0 then
				graph.blocked[id] = true
				graph.cycle_diags[id] = cycle_diag()
				graph.ord[#graph.ord+1] = id
			end
		end
	end

	return graph
end

function M.plan(graph, committed, force_all)
	local affected = {}

	if not committed or force_all then
		for _, id in ipairs(graph.stmt_ord) do
			affected[id] = true
		end
	else
		for _, id in ipairs(graph.stmt_ord) do
			local is_new = not committed.nodes[id]
			local providers_changed = not maps_equal(
				graph.providers[id],
				committed.providers[id]
			)
			local dup_changed = (not not graph.dup_diags[id])
				~= (not not committed.dup_diags[id])
			local blocked_changed = (not not graph.blocked[id])
				~= (not not committed.blocked[id])

			if is_new or providers_changed or dup_changed or blocked_changed then
				affected[id] = true
			end
		end
	end

	local queue = {}
	for _, id in ipairs(graph.stmt_ord) do
		if affected[id] then queue[#queue+1] = id end
	end

	local head = 1
	while head <= #queue do
		local id = queue[head]
		head = head + 1

		for _, dependent in ipairs(graph.dependents[id]) do
			if not affected[dependent] then
				affected[dependent] = true
				queue[#queue+1] = dependent
			end
		end
	end

	local deletions = {}
	if committed then
		for sym, old_owner in pairs(committed.owners) do
			if graph.owners[sym] ~= old_owner then
				deletions[sym] = true
			end
		end
	end

	for id in pairs(affected) do
		local node = graph.nodes[id]
		for _, definition in ipairs(node.outputs) do
			deletions[definition.ref_name] = true
		end
	end

	local eval_ord = {}
	for _, id in ipairs(graph.ord) do
		if affected[id] and not graph.blocked[id] and not graph.dup_diags[id] then
			eval_ord[#eval_ord+1] = id
		end
	end

	return {
		affected = affected,
		deletions = deletions,
		eval_ord = eval_ord,
	}
end

-- for def in graph:definitions() do ... end
function Graph:definitions()
	return coroutine.wrap(function()
		for _, id in ipairs(self.stmt_ord) do
			for _, def in ipairs(self.nodes[id].outputs) do
				coroutine.yield(def)
			end
		end
	end)
end

return M
