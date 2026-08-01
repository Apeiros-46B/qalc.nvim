-- extmark-based dependency graph
local util = require('qalc.util')

local M = {}
M.__index = M

---@param bufnr number The buffer this graph is attached to
function M.new(bufnr)
	local self = setmetatable({}, M)

	self.bufnr = bufnr

	-- extmark_id -> { out_syms, in_syms, norm_expr }
	self.nodes = {}

	-- symbol -> extmark_id
	self.extmarks = {}

	-- track nodes with errors so when we get a result back from C++ we ignore it
	self.had_cycle_error = {} -- extmark_id -> bool
	self.duplicate_syms = {} -- extmark_id -> array[string]

	return self
end

function M:update_node(extmark, out_syms, in_syms, norm_expr)
	local old = self.nodes[extmark] or { out_syms = {}, in_syms = {} }
	local deleted_syms = {}
	local duplicate_syms = {}

	-- register new outputs and guard against duplicates
	local new_outs_set = {}
	local valid_out_syms = {}

	for _, def in ipairs(out_syms) do
		local sym = def.ref_name
		local existing_owner = self.extmarks[sym]

		if existing_owner and existing_owner ~= extmark then
			duplicate_syms[#duplicate_syms+1] = sym
		else
			new_outs_set[sym] = true
			valid_out_syms[#valid_out_syms+1] = def
			self.extmarks[sym] = extmark
		end
	end

	-- prevent self-reference "x = x + 1"
	local clean_in_syms = {}

	if in_syms then
		for _, sym in ipairs(in_syms) do
			if not new_outs_set[sym] then
				clean_in_syms[#clean_in_syms+1] = sym
			end
		end
	end

	-- find outputs that no longer exist on this line
	for _, def in ipairs(old.out_syms) do
		local sym = def.ref_name

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
		local deleted_syms_set = {}

		for _, s in ipairs(deleted_syms) do
			deleted_syms_set[s] = true
		end

		for id, node in pairs(self.nodes) do
			if id ~= extmark then
				for _, in_sym in ipairs(node.in_syms) do
					if deleted_syms_set[in_sym] then
						broken_dependents[#broken_dependents+1] = id
						break
					end
				end
			end
		end
	end

	if #duplicate_syms > 0 then
		self.duplicate_syms[extmark] = duplicate_syms
	else
		self.duplicate_syms[extmark] = nil
	end

	if #valid_out_syms == 0 and #in_syms == 0 and (not norm_expr or norm_expr == '') then
		self.nodes[extmark] = nil
	else
		self.nodes[extmark] = {
			out_syms = valid_out_syms,
			in_syms = clean_in_syms,
			norm_expr = norm_expr,
		}
	end

	return deleted_syms, broken_dependents
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
		self.had_cycle_error[id] = true
		diags[id] = {{
			message = 'Reference cycle found here or in dependents, cannot evaluate',
			severity = vim.diagnostic.severity.ERROR
		}}
	end

	return diags
end

function M:_process_duplicate_errors(target_nodes)
	local dup_diags = {}

	for id in pairs(target_nodes) do
		local syms = self.duplicate_syms[id]
		if syms and #syms > 0 then
			local diags = {}
			for _, sym in ipairs(syms) do
				diags[#diags+1] = {
					message = 'Duplicate definition: "' .. sym .. '" is already defined.',
					severity = vim.diagnostic.severity.ERROR
				}
			end
			dup_diags[id] = diags
		end
	end

	return dup_diags
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
		self.had_cycle_error[id] = nil
	end
	local cycle_diags = self:_process_cycle_errors(cyclic_nodes)
	local duplicate_diags = self:_process_duplicate_errors(affected)

	return cascade, cycle_diags, duplicate_diags
end

-- build the graph on initial load
function M:get_full_sort()
	local adj = self:_build_adj()

	local target_nodes = {}
	-- base target nodes on tracking marks, not self.nodes, so plain math lines are seen
	local marks = vim.api.nvim_buf_get_extmarks(
		self.bufnr,
		util.ns_track,
		{0, 0},
		{-1, -1},
		{}
	)
	for _, mark in ipairs(marks) do
		target_nodes[mark[1]] = true
	end

	local cascade, cyclic_nodes = self:_topo_sort(adj, target_nodes)

	self.had_cycle_error = {}
	local cycle_diags = self:_process_cycle_errors(cyclic_nodes)
	local dup_diags = self:_process_duplicate_errors(target_nodes)

	return cascade, cycle_diags, dup_diags
end

-- for def in graph:definitions() do ... end
function M:definitions()
	return coroutine.wrap(function()
		for _, node in pairs(self.nodes) do
			if node.out_syms then
				for _, def in ipairs(node.out_syms) do
					coroutine.yield(def)
				end
			end
		end
	end)
end

return M
