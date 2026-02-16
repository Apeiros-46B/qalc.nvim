-- extmark-based dependency graph
local M = {}
M.__index = M

---@param bufnr number The buffer this graph is attached to
function M.new(bufnr)
	local self = setmetatable({}, M)
	self.bufnr = bufnr

	-- extmark_id -> { out_syms, in_syms }
	self.nodes = {}

	-- symbol -> extmark_id
	self.extmarks = {}

	-- tracks nodes with cycle errors so when we get a result back from C++ we ignore it
	self.cycle_errors = {}

	return self
end

function M:update_node(extmark, out_syms, in_syms)
	local old = self.nodes[extmark] or { out_syms = {}, in_syms = {} }
	local deleted_syms = {}

	-- register new outputs
	-- if `x` is defined lower in the file, it overwrites extmarks[x]
	local new_outs_set = {}
	for _, sym in ipairs(out_syms) do
		new_outs_set[sym] = true
		self.extmarks[sym] = extmark
	end

	-- find outputs that no longer exist on this line
	for _, sym in ipairs(old.out_syms) do
		if not new_outs_set[sym] then
			-- only clear the symbol->extmark entry if this line was the one providing it
			if self.extmarks[sym] == extmark then
				self.extmarks[sym] = nil
			end
			deleted_syms[#deleted_syms+1] = sym
		end
	end

	-- find nodes whose dependencies were just deleted
	local broken_dependents = {}
	if #deleted_syms > 0 then
		local del_set = {}
		for _, s in ipairs(deleted_syms) do
			del_set[s] = true
		end
		for id, node in pairs(self.nodes) do
			if id ~= extmark then
				for _, in_sym in ipairs(node.in_syms) do
					if del_set[in_sym] then
						broken_dependents[#broken_dependents+1] = id
						break
					end
				end
			end
		end
	end

	if #out_syms == 0 and #in_syms == 0 then
		-- garbage collect
		self.nodes[extmark] = nil
	else
		self.nodes[extmark] = { out_syms = out_syms, in_syms = in_syms }
	end

	return deleted_syms, broken_dependents
end

function M:get_cascade(start_extmark, broken_dependents)
	-- build adjacency list for entire buf
	local adj = {}

	for id in pairs(self.nodes) do
		adj[id] = {}
	end

	for id, node in pairs(self.nodes) do
		local seen_deps = {}
		for _, in_sym in ipairs(node.in_syms) do
			local provider = self.extmarks[in_sym]
			-- avoid self-loops and duplicate edges
			if provider and provider ~= id and not seen_deps[provider] then
				seen_deps[provider] = true
				local t = adj[provider]
				if t then
					t[#t+1] = id
				end
			end
		end
	end

	-- BFS to find only the descendants of the start
	local affected = { [start_extmark] = true }
	local visited = { [start_extmark] = true }
	local queue = { start_extmark }

	-- manually seed broken dependents into BFS queue
	for _, broken_id in ipairs(broken_dependents or {}) do
		if not visited[broken_id] then
			visited[broken_id] = true
			affected[broken_id] = true
			queue[#queue+1] = broken_id
		end
	end

	local head = 1
	while head <= #queue do
		local curr = queue[head]
		head = head + 1
		for _, child in ipairs(adj[curr] or {}) do
			if not visited[child] then
				visited[child] = true
				affected[child] = true
				queue[#queue+1] = child
			end
		end
	end

	-- calculate in-degrees for the affected subgraph
	local sub_in_degree = {}

	for u in pairs(affected) do
		sub_in_degree[u] = 0
	end
	for u in pairs(affected) do
		for _, v in ipairs(adj[u] or {}) do
			if affected[v] then
				sub_in_degree[v] = sub_in_degree[v] + 1
			end
		end
	end

	-- Kahn's algorithm
	for id in pairs(affected) do
		self.cycle_errors[id] = nil
	end

	local zero_in = {}

	for id, deg in pairs(sub_in_degree) do
		if deg == 0 then
			zero_in[#zero_in+1] = id
		end
	end

	local cascade = {}
	local processed = 0
	head = 1

	while head <= #zero_in do
		local u = zero_in[head]
		head = head + 1
		cascade[#cascade+1] = u
		processed = processed + 1

		for _, v in ipairs(adj[u] or {}) do
			if affected[v] then
				sub_in_degree[v] = sub_in_degree[v] - 1
				if sub_in_degree[v] == 0 then
					zero_in[#zero_in+1] = v
				end
			end
		end
	end

	-- detect cycles
	local diags = {}
	local expected_count = 0
	for _ in pairs(affected) do expected_count = expected_count + 1 end

	if processed < expected_count then
		-- any node with a remaining in-degree > 0 is in a cycle
		for id in pairs(affected) do
			if sub_in_degree[id] > 0 then
				self.cycle_errors[id] = true
				diags[id] = {{
					message = 'Reference cycle found, refusing to evaluate',
					severity = vim.diagnostic.severity.ERROR
				}}
				-- add to the cascade the callback sees the diagnostic and skips eval
				cascade[#cascade+1] = id
			end
		end
	end

	return cascade, diags
end

return M
