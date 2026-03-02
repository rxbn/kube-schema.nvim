# kube-schema.nvim

Dynamically inject Kubernetes and CRD schemas into [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) for YAML files in Neovim.
Get validation and completion for your Kubernetes manifests and CRDs, automatically.

![kube-schema nvim](https://github.com/user-attachments/assets/8f2626c7-c2ca-424e-abb9-1dbb60da464e)

---

## ✨ Features

- 🧠 **Auto-detects** `apiVersion` and `kind` in your YAML buffer
- 🔗 **Injects the correct schema** for both built-in Kubernetes resources and CRDs
- ⚡ **Debounced hot reloads** schema on buffer changes to keep editing snappy
- 🧹 **Cleans up** temporary schema files on exit
- 🔔 **Optional notifications** via [fidget.nvim](https://github.com/j-hui/fidget.nvim) when available
- 🛠️ **Zero config** — just install and go!

---

## 🚀 Installation

**[lazy.nvim](https://github.com/folke/lazy.nvim):**

```lua
{
  "rxbn/kube-schema.nvim",
  opts = {},
}
```

---

## ⚙️ Configuration

No configuration is required by default — simply call:

```lua
require("kube-schema").setup()
```

If you want to tune the behavior, `setup()` accepts a few options:

| Option                 | Type    | Default                     | Description                                                                                                                 |
| ---------------------- | ------- | --------------------------- | --------------------------------------------------------------------------------------------------------------------------- |
| `debounce_ms`          | number  | `250`                       | Delay (in ms) before refreshing schemas after text changes. Set to `0` to disable debouncing altogether.                    |
| `cache_dir`            | string  | `vim.fn.stdpath("cache")`   | Directory where the combined schema files are stored.                                                                       |
| `notifications`        | boolean | `true`                      | Whether to surface schema updates/errors via fidget.nvim (when available) or fall back to `vim.notify`.                     |
| `openshift`            | boolean | `false`                     | Enable OpenShift schema support using the generated OpenShift resource index from `melmorabity/openshift-json-schemas`.     |
| `openshift_schema_dir` | string  | `"v4.20-standalone-strict"` | Directory inside `melmorabity/openshift-json-schemas` used when `openshift = true` (for example `v4.20-standalone-strict`). |

Example:

```lua
require("kube-schema").setup({
  debounce_ms = 150,
  cache_dir = vim.fn.stdpath("data") .. "/kube-schema",
  notifications = false,
  openshift = true,
  openshift_schema_dir = "v4.20-standalone-strict",
})
```

> ℹ️ If [fidget.nvim](https://github.com/j-hui/fidget.nvim) is installed, kube-schema.nvim uses it to surface schema refresh progress and errors automatically. Set `notifications = false` to disable all status messages.

If you want to customize or extend further, PRs and issues are always welcome!

In order to prevent the "Matches multiple schemas when only one must validate" error, you can use this helper function to configure `yamlls`:

```lua
yamlls = require("kube-schema").configure_yamlls(),
```

You can also pass custom settings to yamlls, they will be merged with the default settings:

```lua
yamlls = require("kube-schema").configure_yamlls({
    settings = {
        yaml = {
            validate = true,
        },
    },
})
```

You can also use the following manual configuration:

```lua
settings = {
    yaml = {
        schemas = {
            kubernetes = "",
        },
    },
},
```

---

## 🧩 How it works

- On opening a YAML file, the plugin scans for `apiVersion` and `kind`.
- It matches these against built-in Kubernetes resources and CRDs.
- When `openshift = true`, it also matches against a generated OpenShift resource list.
- The correct JSON schema(s) are combined and injected into the `yamlls` LSP client.
- If the file does not look Kubernetes-related yet, the plugin keeps a light-weight watch and upgrades once `apiVersion`/`kind` appear.
- As you edit, the schema updates live (debounced to avoid unnecessary LSP churn).
- Temporary schema files are cleaned up on exit.

---

## 📦 Example

Open a Kubernetes manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: my-app
spec:
  # ... get completion and validation!
```

The correct schema is automatically applied for validation and completion.

---

## 🛠️ Requirements

- [Neovim 0.11+](https://neovim.io/)
- [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) (`yamlls`) enabled in your LSP setup

---

## 🩺 Health Check

Run the built-in health check to verify your setup:

```vim
:checkhealth kube-schema
```

It reports Neovim version, cache directory status, `yamlls` availability, and optional dependencies like fidget.nvim.

---

## 🔍 FAQ

**Q: Does this work with custom CRDs?**
A: Yes! If your CRD is in the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog), it will be picked up automatically.

**Q: Does it support OpenShift resources?**
A: Yes. Set `openshift = true` in `setup()` to fetch schemas from [melmorabity/openshift-json-schemas](https://github.com/melmorabity/openshift-json-schemas/tree/main), and optionally set `openshift_schema_dir` (for example `v4.20-standalone-strict`).
Only resources present in the generated OpenShift index are referenced, so unknown resources are skipped instead of generating broken `$ref` URLs.

**Q: Does it support multiple resources in one file?**
A: Yes, all detected resources are combined into a single schema.

**Q: Does it modify my LSP config?**
A: No, it only updates the schema for the current buffer in `yamlls`.

---

## 🧑‍💻 Contributing

PRs and issues are welcome!
Feel free to open an issue if you have any questions or suggestions.

---

## 📄 License

[MIT](./LICENSE)

---

## 🙏 Credits

- [yannh/kubernetes-json-schema](https://github.com/yannh/kubernetes-json-schema)
- [melmorabity/openshift-json-schemas](https://github.com/melmorabity/openshift-json-schemas/tree/main)
- [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
- [someone-stole-my-name/yaml-companion.nvim](https://github.com/someone-stole-my-name/yaml-companion.nvim)

---

**Happy Kubernetes YAMLing!** 🚢
