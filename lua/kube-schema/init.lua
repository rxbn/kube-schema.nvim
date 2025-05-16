local M = {}

local k8s_combined_schema_template = {
	oneOf = {},
}

M._schema_paths = {}

local builtin_resources = require("kube-schema.builtin_resources")
local crd_kinds = require("kube-schema.crd_resources")

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
	local k8s_combined_schema_path = vim.fn.stdpath("cache") .. "/k8s_combined_schema" .. file_suffix .. ".json"

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
		table.insert(M._schema_paths, k8s_combined_schema_path)
	else
		vim.notify(
			"Failed to create cache file for Kubernetes schema: " .. k8s_combined_schema_path,
			vim.log.levels.ERROR
		)
	end

	if #k8s_combined_schema_template.oneOf > 0 then
		return k8s_combined_schema_path
	end

	return nil
end

---@param bufnr integer
---@param client vim.lsp.Client
---@param api_versions string[]
---@param kinds string[]
M.update_k8s_yaml_schema = function(bufnr, client, api_versions, kinds)
	local buf_uri = vim.uri_from_bufnr(bufnr)
	local override = {}
	local schema = M.generate_k8s_combined_schema(bufnr, api_versions, kinds)
	if not schema then
		return
	end

	override[schema] = buf_uri

	client.settings = vim.tbl_deep_extend("force", client.settings, { yaml = { schemas = override } })
	local success = client:notify("workspace/didChangeConfiguration", {
		settings = client.settings,
	})

	if not success then
		vim.notify("Failed to update YAML schema for Kubernetes", vim.log.levels.ERROR)
	end

	local error = client:request_sync("yaml/get/jsonSchema", {})
	if error and error.err then
		vim.notify("Failed to get Kubernetes schema: " .. error.err, vim.log.levels.ERROR)
	end
end

-- SETUP

M.setup = function()
	local autogroup = vim.api.nvim_create_augroup("kube-schema", { clear = true })
	-- TODO: we should only create this autocmd if its actually a k8s file
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = autogroup,
		callback = function()
			for _, schema in pairs(M._schema_paths) do
				local cache_file = io.open(schema, "r")
				if cache_file then
					cache_file:close()
					os.remove(schema)
				end
			end
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

			local api_versions, kinds = M.extract_k8s_api_and_kind(ev.buf)
			if not api_versions or not kinds then
				return
			end

			M.update_k8s_yaml_schema(ev.buf, client, api_versions, kinds)

			vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
				group = autogroup,
				buffer = ev.buf,
				callback = function()
					api_versions, kinds = M.extract_k8s_api_and_kind(ev.buf)
					if not api_versions or not kinds then
						return
					end
					M.update_k8s_yaml_schema(ev.buf, client, api_versions, kinds)
				end,
			})
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
