-- interface with Qalculate and return formatted results

local jobs = {}

-- TODO
local function start(bufnr)
	
end

local function kill(bufnr)
	vim.fn.jobstop(jobs[bufnr])
	jobs[bufnr] = nil
end

-- TODO
local function run(bufnr, input, first, last)
	if jobs[bufnr] == nil then
		start(bufnr)
	end
end

return {
	run  = run,
	kill = kill,
}
