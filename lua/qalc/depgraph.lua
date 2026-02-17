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

	-- track nodes with errors so when we get a result back from C++ we ignore it
	self.cycle_errors = {} -- nodes with cycle errors
	self.duplicate_errors = {} -- nodes that try to redefine existing variables

	return self
end

function M:update_node(extmark, out_syms, in_syms)
	local old = self.nodes[extmark] or { out_syms = {}, in_syms = {} }
	local deleted_syms = {}
	local diags = {}

	-- register new outputs and guard against duplicates
	local new_outs_set = {}
	local valid_out_syms = {}
	for _, sym in ipairs(out_syms) do
		local existing_owner = self.extmarks[sym]
		if existing_owner and existing_owner ~= extmark then
			diags[#diags+1] = {
				message = 'Duplicate definition: "' .. sym .. '" is already defined.',
				severity = vim.diagnostic.severity.ERROR
			}
		else
			new_outs_set[sym] = true
			valid_out_syms[#valid_out_syms+1] = sym
			self.extmarks[sym] = extmark
		end
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

	if #diags > 0 then
		self.duplicate_errors[extmark] = diags
	else
		self.duplicate_errors[extmark] = nil
	end

	if #valid_out_syms == 0 and #in_syms == 0 then
		-- garbage collect
		self.nodes[extmark] = nil
	else
		self.nodes[extmark] = { out_syms = valid_out_syms, in_syms = in_syms }
	end

	return deleted_syms, broken_dependents, diags
end

-- build adjacency list for entire buf
function M:_build_adj()
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

	return adj
end

-- topological sort on a specific subset of nodes (Kahn's algorithm)
-- returns the sorted cascade array and array of nodes in cycles
function M:_topo_sort(adj, target_nodes)
	-- calculate in-degrees for the affected subgraph
	local sub_in_degree = {}

	for u in pairs(target_nodes) do
		sub_in_degree[u] = 0
	end
	for u in pairs(target_nodes) do
		for _, v in ipairs(adj[u] or {}) do
			if target_nodes[v] then
				sub_in_degree[v] = sub_in_degree[v] + 1
			end
		end
	end

	local zero_in = {}

	for id, deg in pairs(sub_in_degree) do
		if deg == 0 then
			zero_in[#zero_in+1] = id
		end
	end

	local cascade = {}

	local processed = 0
	local head = 1
	while head <= #zero_in do
		local u = zero_in[head]
		head = head + 1
		cascade[#cascade+1] = u
		processed = processed + 1

		for _, v in ipairs(adj[u] or {}) do
			if target_nodes[v] then
				sub_in_degree[v] = sub_in_degree[v] - 1
				if sub_in_degree[v] == 0 then
					zero_in[#zero_in+1] = v
				end
			end
		end
	end

	-- detect cycles
	local cyclic_nodes = {}
	local expected_count = 0
	for _ in pairs(target_nodes) do
		expected_count = expected_count + 1
	end

	if processed < expected_count then
		-- any node with a remaining in-degree > 0 is in a cycle
		for id in pairs(target_nodes) do
			if sub_in_degree[id] > 0 then
				cyclic_nodes[#cyclic_nodes+1] = id
				-- add to the cascade the callback sees the diagnostic and skips eval
				cascade[#cascade+1] = id
			end
		end
	end

	return cascade, cyclic_nodes
end

function M:_process_cycle_errors(cyclic_nodes)
	local diags = {}

	for _, id in ipairs(cyclic_nodes) do
		self.cycle_errors[id] = true
		diags[id] = {{
			message = 'Reference cycle found, refusing to evaluate',
			severity = vim.diagnostic.severity.ERROR
		}}
	end

	return diags
end

function M:get_cascade(start_extmark, broken_dependents)
	local adj = self:_build_adj()

	-- BFS to find only the descendants of the start and broken nodes
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

	-- topologically sort the affected subgraph
	local cascade, cyclic_nodes = self:_topo_sort(adj, affected)

	for id in pairs(affected) do
		self.cycle_errors[id] = nil
	end
	local cycle_diags = self:_process_cycle_errors(cyclic_nodes)

	return cascade, cycle_diags
end

-- build the graph on initial load
function M:get_full_sort()
	local adj = self:_build_adj()

	local target_nodes = {}
	for id in pairs(self.nodes) do
		target_nodes[id] = true
	end

	local cascade, cyclic_nodes = self:_topo_sort(adj, target_nodes)

	self.cycle_errors = {}
	local cycle_diags = self:_process_cycle_errors(cyclic_nodes)

	return cascade, cycle_diags
end

return M
