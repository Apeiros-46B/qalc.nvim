local lib = require('libqalcbridge')

lib.init()
local now = os.clock()
print(vim.inspect(lib.eval('# this is a comment')))
print("elapsed:", os.clock() - now)
