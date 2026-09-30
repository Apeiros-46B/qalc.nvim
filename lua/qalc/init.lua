-- initialize plugin
local config = require('qalc.config')
local buffer = require('qalc.buffer')

return {
	cfg        = config.cfg,
	setup      = config.setup,
	set_option = config.set_option,
	new_buf    = buffer.new_buf,
	attach     = buffer.attach,
}
