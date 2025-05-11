local M = {}

local k8s_combined_schema_template = {
	oneOf = {},
}

M._schema_paths = {}

local builtin_resources = require("kube-schema.builtin_resources")

---@param bufnr integer
---@return string | nil
M.get_kubernetes_json_schema = function(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)

	local api_versions = {}
	local kinds = {}

	for _, line in ipairs(lines) do
		local api_version = line:match("^apiVersion:%s*(%S+)")
		local kind = line:match("^kind:%s*(%S+)")

		if api_version then
			table.insert(api_versions, api_version)
		end
		if kind then
			table.insert(kinds, kind)
		end
	end

	local file_path = vim.api.nvim_buf_get_name(bufnr)
	local file_suffix = file_path:gsub("[/:\\]", "_")
	local k8s_combined_schema_path = vim.fn.stdpath("cache") .. "/k8s_combined_schema" .. file_suffix .. ".json"

	k8s_combined_schema_template.oneOf = {}

	for i, api_version in ipairs(api_versions) do
		local kind = kinds[i]
		if api_version and kind then
			local is_builtin = vim.tbl_contains(builtin_resources, kind)

			if is_builtin then
				table.insert(k8s_combined_schema_template.oneOf, {
					["$ref"] = "https://raw.githubusercontent.com/yannh/kubernetes-json-schema/refs/heads/master/master-standalone-strict/"
						.. string.lower(kind)
						.. ".json",
				})
			else
				local api_group = api_version:match("^[^/]+")
				local api_version_suffix = api_version:match("/(v%d+.*)")

				if api_group and api_version_suffix then
					table.insert(k8s_combined_schema_template.oneOf, {
						["$ref"] = "https://raw.githubusercontent.com/datreeio/CRDs-catalog/refs/heads/main/"
							.. api_group
							.. "/"
							.. string.lower(kind)
							.. "_"
							.. api_version_suffix
							.. ".json",
					})
				end
			end
		end
	end

	local json_output = vim.fn.json_encode(k8s_combined_schema_template)
	local cache_file = io.open(k8s_combined_schema_path, "w")
	if cache_file then
		cache_file:write(json_output)
		cache_file:close()
		M._schema_paths[k8s_combined_schema_path] = true
	else
		vim.api.nvim_echo(
			{ { "Failed to write Kubernetes schema cache file: " .. k8s_combined_schema_path, "ErrorMsg" } },
			true,
			{}
		)
	end

	if #k8s_combined_schema_template.oneOf > 0 then
		return k8s_combined_schema_path
	end

	return nil
end

---@param bufnr integer
M.schema = function(bufnr)
	local client = vim.lsp.get_clients({ bufnr = bufnr, name = "yamlls" })[1]
	if not client then
		return
	end

	local buf_uri = vim.uri_from_bufnr(bufnr)
	local settings = client.settings
	local override = {}
	local schema = M.get_kubernetes_json_schema(bufnr)
	if not schema then
		return
	end

	override[schema] = buf_uri

	settings = vim.tbl_deep_extend("force", settings, { yaml = { schemas = override } })
	client.settings = vim.tbl_deep_extend("force", settings, { yaml = { schemas = override } })
	local success = client:notify("workspace/didChangeConfiguration", {
		settings = settings,
	})

	if not success then
		vim.notify("Failed to update YAML schema for Kubernetes", vim.log.levels.ERROR)
	end

	vim.lsp.buf_request_sync(bufnr, "yaml/get/jsonSchema")
end

M.setup = function()
	local autogroup = vim.api.nvim_create_augroup("kube-schema", { clear = true })
	vim.api.nvim_create_autocmd("VimLeavePre", {
		group = autogroup,
		callback = function()
			for schema, _ in pairs(M._schema_paths) do
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
			vim.api.nvim_create_autocmd({ "TextChanged", "TextChangedI" }, {
				group = autogroup,
				buffer = ev.buf,
				callback = function()
					M.schema(ev.buf)
				end,
			})
			M.schema(ev.buf)
		end,
	})
end

return M
