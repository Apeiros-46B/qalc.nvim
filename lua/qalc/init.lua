-- initialize plugin
local config = require('qalc.config')
local buffer = require('qalc.buffer')
-- TODO: this .init() call takes about 60ms on my machine, is there any way we can defer it or just rely on users lazy loading the plugin on *.qalc?
-- additional: see if it's possible to asynchonously load definitions on the C++ side
local calc   = require('qalc.lib').init()

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
