local M = {}

local function get_health()
	local ok, health = pcall(require, "vim.health")
	if ok then
		return health
	end
	return require("health")
end

local function get_reporter(health)
	return {
		start = health.start or health.report_start,
		ok = health.ok or health.report_ok,
		info = health.info or health.report_info,
		warn = health.warn or health.report_warn,
		error = health.error or health.report_error,
	}
end

local function version_at_least(min_major, min_minor)
	if not vim.version then
		return false
	end

	local version = vim.version()
	if version.major ~= min_major then
		return version.major > min_major
	end

	return version.minor >= min_minor
end

local function get_lsp_clients()
	if vim.lsp and vim.lsp.get_clients then
		return vim.lsp.get_clients()
	end
	if vim.lsp and vim.lsp.get_active_clients then
		return vim.lsp.get_active_clients()
	end
	return {}
end

local function check_cache_dir(reporter, config)
	local cache_dir = config.cache_dir
	if not cache_dir or cache_dir == "" then
		reporter.error("cache_dir is not configured")
		return
	end

	local uv = vim.uv or vim.loop
	local stat = uv and uv.fs_stat and uv.fs_stat(cache_dir) or nil
	if not stat then
		reporter.warn(("cache_dir does not exist yet (will be created on demand): %s"):format(cache_dir))
		return
	end

	local writable = vim.fn.filewritable(cache_dir)
	if writable ~= 2 then
		reporter.error(("cache_dir is not writable: %s"):format(cache_dir))
		return
	end

	reporter.ok(("cache_dir is writable: %s"):format(cache_dir))
end

local function check_yamlls(reporter)
	local has_yamlls = false
	for _, client in ipairs(get_lsp_clients()) do
		if client.name == "yamlls" then
			has_yamlls = true
			break
		end
	end

	if has_yamlls then
		reporter.ok("yaml-language-server is active")
	else
		reporter.warn("yaml-language-server is not active (set up yamlls in your LSP config)")
	end
end

local function check_resources(reporter)
	local builtin = require("kube-schema.builtin_resources")
	local crds = require("kube-schema.crd_resources")

	if type(builtin) == "table" and #builtin > 0 then
		reporter.ok(("builtin resource list loaded (%d entries)"):format(#builtin))
	else
		reporter.warn("builtin resource list is empty or unavailable")
	end

	if type(crds) == "table" and #crds > 0 then
		reporter.ok(("CRD resource list loaded (%d entries)"):format(#crds))
	else
		reporter.warn("CRD resource list is empty or unavailable")
	end
end

local function check_optional_deps(reporter)
	local ok = pcall(require, "fidget")
	if ok then
		reporter.ok("fidget.nvim detected for notifications")
	else
		reporter.info("fidget.nvim not found (vim.notify will be used instead)")
	end
end

M.check = function()
	local health = get_health()
	local reporter = get_reporter(health)

	reporter.start("kube-schema.nvim")

	if version_at_least(0, 11) then
		reporter.ok("Neovim >= 0.11")
	else
		reporter.error("Neovim >= 0.11 is required")
	end

	local config = require("kube-schema").config or {}
	check_cache_dir(reporter, config)
	check_yamlls(reporter)
	check_resources(reporter)
	check_optional_deps(reporter)

	if config.notifications == false then
		reporter.info("notifications are disabled (config.notifications = false)")
	end
end

return M
