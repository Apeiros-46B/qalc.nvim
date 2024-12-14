-- initialize plugin
local config = require('qalc.config')
local buffer = require('qalc.buffer')

return {
	cfg     = config.cfg,
	setup   = config.setup,
	new_buf = buffer.new_buf,
	attach  = buffer.attach,
	detach  = buffer.detach,
	yank    = buffer.yank,
}
