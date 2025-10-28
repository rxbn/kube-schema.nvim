local eq = assert.are.same

local function reload_module()
	package.loaded["kube-schema"] = nil
	package.loaded["kube-schema.init"] = nil
	return require("kube-schema")
end

local function make_client()
	local notifications = {}
	local requests = {}
	local client = {
		name = "yamlls",
		settings = {},
		notify_calls = notifications,
		request_calls = requests,
	}

	function client:notify(method, payload)
		table.insert(notifications, { method = method, payload = payload })
		return true
	end

	function client:request_sync(method, payload)
		table.insert(requests, { method = method, payload = payload })
		return {}
	end

	function client:is_stopped()
		return false
	end

	return client
end

describe("kube-schema.nvim", function()
	local kube_schema
	local tmpdir
	local buffers
	local original_notify
	local original_get_client

	local function new_buffer(name, lines)
		local buf = vim.api.nvim_create_buf(false, true)
		vim.api.nvim_buf_set_name(buf, tmpdir .. "/" .. name)
		vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
		table.insert(buffers, buf)
		return buf
	end

	before_each(function()
		tmpdir = vim.fn.tempname()
		vim.fn.mkdir(tmpdir, "p")
		buffers = {}

		kube_schema = reload_module()
		kube_schema.config.cache_dir = tmpdir
		kube_schema.config.debounce_ms = 0
		kube_schema._schema_paths = {}
		kube_schema._debounce_timers = {}
		kube_schema._buffer_state = {}
		kube_schema._fidget_checked = false
		kube_schema._fidget_notify = nil

		original_notify = vim.notify
		original_get_client = vim.lsp.get_client_by_id
	end)

	after_each(function()
		vim.notify = original_notify
		vim.lsp.get_client_by_id = original_get_client

		for _, buf in ipairs(buffers) do
			if vim.api.nvim_buf_is_valid(buf) then
				vim.api.nvim_buf_delete(buf, { force = true })
			end
		end

		if tmpdir and vim.fn.isdirectory(tmpdir) == 1 then
			vim.fn.delete(tmpdir, "rf")
		end

		package.loaded["kube-schema"] = nil
		package.loaded["kube-schema.init"] = nil
		package.loaded["fidget"] = nil
	end)

	it("extracts apiVersion and kind values", function()
		local buf = new_buffer("deployment.yaml", {
			"# comment",
			"apiVersion: Apps/v1",
			"kind: Deployment",
			"metadata:",
			"  name: demo",
		})

		local apis, kinds = kube_schema.extract_k8s_api_and_kind(buf)

		eq({ "apps/v1" }, apis)
		eq({ "deployment" }, kinds)
	end)

	it("updates schemas once per fingerprint and falls back to vim.notify", function()
		local buf = new_buffer("deployment.yaml", {
			"apiVersion: apps/v1",
			"kind: Deployment",
			"metadata:",
			"  name: demo",
		})

		local client = make_client()
		vim.lsp.get_client_by_id = function()
			return client
		end

		local notifications = {}
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		local apis, kinds = kube_schema.extract_k8s_api_and_kind(buf)

		local ok = kube_schema.update_k8s_yaml_schema(buf, client, apis, kinds)
		assert.is_true(ok)
		assert.equals(1, #client.notify_calls)
		assert.equals("workspace/didChangeConfiguration", client.notify_calls[1].method)
		assert.equals(1, #notifications)
		assert.matches("applied schema", notifications[1].msg)
		local schema_path = next(client.notify_calls[1].payload.settings.yaml.schemas)
		assert.is_not_nil(schema_path)
		assert.equals(1, vim.fn.filereadable(schema_path))

		local ok_again = kube_schema.update_k8s_yaml_schema(buf, client, apis, kinds)
		assert.is_true(ok_again)
		assert.equals(1, #client.notify_calls)
		assert.equals(1, #notifications)

		vim.api.nvim_buf_set_lines(buf, 1, 2, false, { "kind: StatefulSet" })
		local apis2, kinds2 = kube_schema.extract_k8s_api_and_kind(buf)
		local ok_third = kube_schema.update_k8s_yaml_schema(buf, client, apis2, kinds2)
		assert.is_true(ok_third)
		assert.equals(2, #client.notify_calls)
		assert.equals(2, #notifications)
		assert.matches("statefulset", notifications[2].msg)
	end)

	it("uses fidget notifications when available", function()
		local buf = new_buffer("deployment.yaml", {
			"apiVersion: apps/v1",
			"kind: Deployment",
		})

		local client = make_client()
		vim.lsp.get_client_by_id = function()
			return client
		end

		local fidget_messages = {}
		package.loaded["fidget"] = {
			notify = function(msg, level)
				table.insert(fidget_messages, { msg = msg, level = level })
			end,
		}

		local fallback_called = false
		vim.notify = function()
			fallback_called = true
		end

		kube_schema._fidget_checked = false
		kube_schema._fidget_notify = nil

		local apis, kinds = kube_schema.extract_k8s_api_and_kind(buf)
		local ok = kube_schema.update_k8s_yaml_schema(buf, client, apis, kinds)

		assert.is_true(ok)
		assert.is_false(fallback_called)
		assert.equals(1, #fidget_messages)
		assert.matches("applied schema", fidget_messages[1].msg)
	end)

	it("allows disabling notifications", function()
		local buf = new_buffer("deployment.yaml", {
			"apiVersion: apps/v1",
			"kind: Deployment",
		})

		local client = make_client()
		vim.lsp.get_client_by_id = function()
			return client
		end

		kube_schema.config.notifications = false

		local fallback_called = false
		vim.notify = function()
			fallback_called = true
		end

		local apis, kinds = kube_schema.extract_k8s_api_and_kind(buf)
		local ok = kube_schema.update_k8s_yaml_schema(buf, client, apis, kinds)

		assert.is_true(ok)
		assert.is_false(fallback_called)
	end)
end)
