-- initialize plugin
local config = require('qalc.config')
local buffer = require('qalc.buffer')
local calc   = require('libqalcbridge').init()

return {
	cfg     = config.cfg,
	setup   = function(new_cfg)
		config.setup(new_cfg)
		require('qalc.commands')
	end,
	new_buf = buffer.new_buf,
	attach  = buffer.attach,
	detach  = buffer.detach,
	yank    = buffer.yank,
	__calc  = calc, -- keep it alive
}
