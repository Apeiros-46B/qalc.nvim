local lib = require('libqalcbridge')

lib.init()
print(vim.inspect(lib.eval('solve(x^2 = -4)')))
