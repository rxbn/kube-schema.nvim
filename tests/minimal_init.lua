vim.env.XDG_CACHE_HOME = vim.fn.getcwd() .. "/.test-cache"

local root = vim.fn.getcwd()
local plenary_path = root .. "/.deps/plenary.nvim"

vim.opt.runtimepath:append(root)
vim.opt.runtimepath:append(plenary_path)

pcall(vim.fn.mkdir, vim.env.XDG_CACHE_HOME, "p")

pcall(require, "plenary.busted")
