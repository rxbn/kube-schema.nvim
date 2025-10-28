local M = {}

local uv = vim.uv or vim.loop

local default_config = {
	cache_dir = vim.fn.stdpath("cache"),
	debounce_ms = 250,
	notifications = true,
}

local k8s_combined_schema_template = {
	oneOf = {},
}

M.config = {
	cache_dir = default_config.cache_dir,
	debounce_ms = default_config.debounce_ms,
	notifications = default_config.notifications,
}

M._schema_paths = {}
M._debounce_timers = {}
M._buffer_state = {}
M._fidget_checked = false
M._fidget_notify = nil

local builtin_resources = require("kube-schema.builtin_resources")
local crd_kinds = require("kube-schema.crd_resources")

local function joinpath(...)
	if vim.fs and vim.fs.joinpath then
		return vim.fs.joinpath(...)
	end

	local sep = package.config:sub(1, 1)
	local parts = { ... }
	local path = (parts[1] or ""):gsub("[/\\]", sep)

	for i = 2, #parts do
		local part = parts[i] or ""
		if part ~= "" then
			part = part:gsub("^[\\/]+", ""):gsub("[\\/]+$", "")
			if path == "" or path:sub(-1) == sep then
				path = path .. part
			else
				path = path .. sep .. part
			end
		end
	end

	return path
end

local function ensure_fidget_notifier()
	if M._fidget_checked then
		return M._fidget_notify
	end

	M._fidget_checked = true

	local ok, fidget = pcall(require, "fidget")
	if ok and type(fidget) == "table" and type(fidget.notify) == "function" then
		M._fidget_notify = fidget.notify
	else
		M._fidget_notify = false
	end

	return M._fidget_notify
end

local function notify(message, level)
	if M.config.notifications == false then
		return
	end

	level = level or vim.log.levels.INFO
	local notifier = ensure_fidget_notifier()
	if type(notifier) == "function" then
		local ok = pcall(notifier, message, level)
		if ok then
			return
		end
	end

	vim.notify(message, level)
end

local function get_buffer_state(bufnr)
	local state = M._buffer_state[bufnr]
	if not state then
		state = {}
		M._buffer_state[bufnr] = state
	end
	return state
end

local function remove_schema_path(schema_path, excluded_bufnr)
	if not schema_path then
		return
	end

	for bufnr, state in pairs(M._buffer_state) do
		if bufnr ~= excluded_bufnr and state.schema_path == schema_path then
			return
		end
	end

	M._schema_paths[schema_path] = nil
	pcall(os.remove, schema_path)
end

local function clear_debounce_timer(bufnr)
	local timer = M._debounce_timers[bufnr]
	if timer then
		timer:stop()
		timer:close()
		M._debounce_timers[bufnr] = nil
	end
end

local function clear_buffer_state(bufnr)
	clear_debounce_timer(bufnr)

	local state = M._buffer_state[bufnr]
	if not state then
		return
	end

	if state.schema_autocmd_id then
		pcall(vim.api.nvim_del_autocmd, state.schema_autocmd_id)
	end
	if state.detection_autocmd_id then
		pcall(vim.api.nvim_del_autocmd, state.detection_autocmd_id)
	end
	if state.cleanup_autocmd_id then
		pcall(vim.api.nvim_del_autocmd, state.cleanup_autocmd_id)
	end

	remove_schema_path(state.schema_path, bufnr)

	M._buffer_state[bufnr] = nil
end

local function normalize_identifiers(api_versions, kinds)
	local normalized_api_versions = {}
	local normalized_kinds = {}
	local limit = math.min(#api_versions, #kinds)

	for i = 1, limit do
		normalized_api_versions[i] = api_versions[i]
		normalized_kinds[i] = kinds[i]
	end

	return normalized_api_versions, normalized_kinds
end

local function format_schema_summary(api_versions, kinds)
	local summary = {}
	local limit = math.min(#api_versions, #kinds)
	for i = 1, limit do
		summary[i] = api_versions[i] .. ":" .. kinds[i]
	end

	return table.concat(summary, ", ")
end

local function build_fingerprint(api_versions, kinds)
	if #api_versions == 0 then
		return nil
	end

	local parts = {}
	for i = 1, #api_versions do
		parts[i] = api_versions[i] .. ":" .. kinds[i]
	end

	return table.concat(parts, "\031")
end

local function debounce_schema_update(bufnr, callback)
	if not uv or not uv.new_timer then
		callback()
		return
	end

	clear_debounce_timer(bufnr)

	local timer = uv.new_timer()
	if not timer then
		callback()
		return
	end

	M._debounce_timers[bufnr] = timer

	timer:start(M.config.debounce_ms, 0, function()
		timer:stop()
		timer:close()
		if M._debounce_timers[bufnr] == timer then
			M._debounce_timers[bufnr] = nil
		end
		vim.schedule(callback)
	end)
end

local function refresh_schema(bufnr, client_id)
	if not vim.api.nvim_buf_is_valid(bufnr) then
		return false
	end

	local client = vim.lsp.get_client_by_id(client_id)
	if not client or client.name ~= "yamlls" or (client.is_stopped and client:is_stopped()) then
		return false
	end

	local api_versions, kinds = M.extract_k8s_api_and_kind(bufnr)
	if not api_versions or not kinds then
		return false
	end

	api_versions, kinds = normalize_identifiers(api_versions, kinds)
	if #api_versions == 0 then
		return false
	end

	return M.update_k8s_yaml_schema(bufnr, client, api_versions, kinds)
end

local function register_schema_autocmd(bufnr, client_id, group)
	local state = get_buffer_state(bufnr)
	if state.schema_autocmd_id then
		return
	end

	if state.detection_autocmd_id then
		pcall(vim.api.nvim_del_autocmd, state.detection_autocmd_id)
		state.detection_autocmd_id = nil
	end

	state.client_id = client_id
	state.schema_autocmd_id = vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
		group = group,
		buffer = bufnr,
		callback = function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				clear_buffer_state(bufnr)
				return
			end

			debounce_schema_update(bufnr, function()
				local has_schema = refresh_schema(bufnr, client_id)
				if not has_schema then
					local current_state = get_buffer_state(bufnr)
					current_state.fingerprint = nil
				end
			end)
		end,
	})

	M._buffer_state[bufnr] = state
end

local function register_detection_autocmd(bufnr, client_id, group)
	local state = get_buffer_state(bufnr)
	if state.detection_autocmd_id then
		return
	end

	state.client_id = client_id
	state.detection_autocmd_id = vim.api.nvim_create_autocmd({ "InsertLeave", "BufWritePost" }, {
		group = group,
		buffer = bufnr,
		callback = function()
			if not vim.api.nvim_buf_is_valid(bufnr) then
				clear_buffer_state(bufnr)
				return
			end

			if refresh_schema(bufnr, client_id) then
				register_schema_autocmd(bufnr, client_id, group)
				local current_state = get_buffer_state(bufnr)
				if current_state.detection_autocmd_id then
					pcall(vim.api.nvim_del_autocmd, current_state.detection_autocmd_id)
					current_state.detection_autocmd_id = nil
				end
			end
		end,
	})

	M._buffer_state[bufnr] = state
end

---@param bufnr integer
---@return string[] | nil, string[] | nil
M.extract_k8s_api_and_kind = function(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local api_versions = {}
	local kinds = {}

	for _, line in ipairs(lines) do
		local api_version = line:match("^apiVersion:%s*(%S+)")
		local kind = line:match("^kind:%s*(%S+)")

		if api_version then
			table.insert(api_versions, string.lower(api_version))
		end
		if kind then
			table.insert(kinds, string.lower(kind))
		end
	end

	return api_versions, kinds
end

---@param bufnr integer
---@param api_versions string[]
---@param kinds string[]
---@return string | nil
M.generate_k8s_combined_schema = function(bufnr, api_versions, kinds)
	local file_path = vim.api.nvim_buf_get_name(bufnr)
	local file_suffix = file_path:gsub("[/:\\]", "_")
	local cache_dir = M.config.cache_dir or default_config.cache_dir
	if not cache_dir or cache_dir == "" then
		notify("kube-schema.nvim: cache_dir is not configured", vim.log.levels.ERROR)
		return nil
	end

	local ok, err = pcall(vim.fn.mkdir, cache_dir, "p")
	if not ok then
		notify("kube-schema.nvim: failed to ensure cache dir: " .. tostring(err), vim.log.levels.ERROR)
		return nil
	end

	local k8s_combined_schema_path = vim.fs.joinpath(cache_dir, "k8s_combined_schema" .. file_suffix .. ".json")

	k8s_combined_schema_template.oneOf = {}

	for i, api_version in ipairs(api_versions) do
		local kind = kinds[i]
		if api_version and kind then
			local api_group = api_version:match("^[^/]+")
			local is_builtin = vim.tbl_contains(builtin_resources, api_version .. ":" .. kind)
			local is_crd = vim.tbl_contains(crd_kinds, api_version .. ":" .. kind)

			if is_builtin then
				table.insert(k8s_combined_schema_template.oneOf, {
					["$ref"] = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/refs/heads/master/master-standalone-strict/"
						.. kind
						.. ".json",
				})
			elseif is_crd then
				local api_version_suffix = api_version:match("/?(v%d+.*)")
				table.insert(k8s_combined_schema_template.oneOf, {
					["$ref"] = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/refs/heads/main/"
						.. api_group
						.. "/"
						.. kind
						.. "_"
						.. api_version_suffix
						.. ".json",
				})
			end
		end
	end

	local json_output = vim.fn.json_encode(k8s_combined_schema_template)
	local cache_file = io.open(k8s_combined_schema_path, "w")
	if cache_file then
		cache_file:write(json_output)
		cache_file:close()
	else
		notify("Failed to create cache file for Kubernetes schema: " .. k8s_combined_schema_path, vim.log.levels.ERROR)
	end

	if #k8s_combined_schema_template.oneOf > 0 then
		M._schema_paths[k8s_combined_schema_path] = true
		return k8s_combined_schema_path
	end

	return nil
end

---@param bufnr integer
---@param client vim.lsp.Client
---@param api_versions string[]
---@param kinds string[]
M.update_k8s_yaml_schema = function(bufnr, client, api_versions, kinds)
	local fingerprint = build_fingerprint(api_versions, kinds)
	if not fingerprint then
		local state = M._buffer_state[bufnr]
		if state then
			remove_schema_path(state.schema_path, bufnr)
			state.schema_path = nil
			state.fingerprint = nil
		end
		return false
	end

	local state = get_buffer_state(bufnr)
	if
		state.fingerprint == fingerprint
		and state.schema_path
		and vim.fn.filereadable(state.schema_path) == 1
	then
		return true
	end

	local buf_uri = vim.uri_from_bufnr(bufnr)
	local override = {}
	local previous_schema = state.schema_path
	local schema = M.generate_k8s_combined_schema(bufnr, api_versions, kinds)
	if not schema then
		remove_schema_path(previous_schema, bufnr)
		state.schema_path = nil
		state.fingerprint = nil
		return false
	end

	if previous_schema and previous_schema ~= schema then
		remove_schema_path(previous_schema, bufnr)
	end

	override[schema] = buf_uri

	client.settings = vim.tbl_deep_extend("force", client.settings, { yaml = { schemas = override } })
	local success = client:notify("workspace/didChangeConfiguration", {
		settings = client.settings,
	})

	if not success then
		notify("Failed to update YAML schema for Kubernetes", vim.log.levels.ERROR)
		return false
	end

	local error = client:request_sync("yaml/get/jsonSchema", {})
	if error and error.err then
		notify("Failed to get Kubernetes schema: " .. error.err, vim.log.levels.ERROR)
		return false
	end

	local should_notify_success = state.notified_fingerprint ~= fingerprint

	state.schema_path = schema
	state.fingerprint = fingerprint
	state.notified_fingerprint = fingerprint
	M._buffer_state[bufnr] = state

	if should_notify_success then
		local summary = format_schema_summary(api_versions, kinds)
		if summary ~= "" then
			notify("kube-schema.nvim: applied schema for " .. summary, vim.log.levels.INFO)
		end
	end

	return true
end

-- SETUP

M.setup = function(opts)
	opts = opts or {}
	if opts.debounce_ms ~= nil then
		opts.debounce_ms = tonumber(opts.debounce_ms) or default_config.debounce_ms
	end
	if opts.notifications ~= nil then
		opts.notifications = not not opts.notifications
	end

	M.config = vim.tbl_deep_extend("force", {}, default_config, M.config or {}, opts)

	if not M.config.cache_dir or M.config.cache_dir == "" then
		M.config.cache_dir = default_config.cache_dir
	end

	if type(M.config.debounce_ms) ~= "number" or M.config.debounce_ms < 0 then
		M.config.debounce_ms = default_config.debounce_ms
	end
	if type(M.config.notifications) ~= "boolean" then
		M.config.notifications = default_config.notifications
	end

	local autogroup = vim.api.nvim_create_augroup("kube-schema", { clear = true })

	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = autogroup,
		callback = function()
			local bufnrs = vim.tbl_keys(M._buffer_state)
			for _, bufnr in ipairs(bufnrs) do
				clear_buffer_state(bufnr)
			end

			for schema_path in pairs(M._schema_paths) do
				pcall(os.remove, schema_path)
				M._schema_paths[schema_path] = nil
			end
		end,
	})

	vim.api.nvim_create_autocmd("LspDetach", {
		group = autogroup,
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if not client or client.name ~= "yamlls" then
				return
			end

			clear_buffer_state(ev.buf)
		end,
	})

	vim.api.nvim_create_autocmd("LspAttach", {
		group = autogroup,
		pattern = { "*.yaml", "*.yml" },
		callback = function(ev)
			local client = vim.lsp.get_client_by_id(ev.data.client_id)
			if not client or client.name ~= "yamlls" then
				return
			end

			local bufnr = ev.buf
			local client_id = ev.data.client_id

			local state = get_buffer_state(bufnr)
			if not state.cleanup_autocmd_id then
				state.cleanup_autocmd_id = vim.api.nvim_create_autocmd("BufWipeout", {
					group = autogroup,
					buffer = bufnr,
					callback = function()
						clear_buffer_state(bufnr)
					end,
				})
			end

			state.client_id = client_id
			M._buffer_state[bufnr] = state

			if refresh_schema(bufnr, client_id) then
				register_schema_autocmd(bufnr, client_id, autogroup)
			else
				register_detection_autocmd(bufnr, client_id, autogroup)
			end
		end,
	})
end

---@param config table | nil
---@return table
M.configure_yamlls = function(config)
	config = config or {}

	config = vim.tbl_deep_extend("force", config, {
		settings = {
			yaml = {
				schemas = {
					kubernetes = "",
				},
			},
		},
	})

	return config
end

return M
