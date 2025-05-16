# kube-schema.nvim

Dynamically inject Kubernetes and CRD schemas into [yaml-language-server](https://github.com/redhat-developer/yaml-language-server) for YAML files in Neovim.
Get validation and completion for your Kubernetes manifests and CRDs, automatically.

![kube-schema nvim](https://github.com/user-attachments/assets/8f2626c7-c2ca-424e-abb9-1dbb60da464e)

---

## ✨ Features

- 🧠 **Auto-detects** `apiVersion` and `kind` in your YAML buffer
- 🔗 **Injects the correct schema** for both built-in Kubernetes resources and CRDs
- ⚡ **Hot reloads** schema on buffer changes
- 🧹 **Cleans up** temporary schema files on exit
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

No configuration is required by default.
Just call `require("kube-schema").setup()` in your plugin manager.

If you want to customize or extend, PRs and issues are welcome!

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
- The correct JSON schema(s) are combined and injected into the `yamlls` LSP client.
- As you edit, the schema updates live.
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

## 🔍 FAQ

**Q: Does this work with custom CRDs?**
A: Yes! If your CRD is in the [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog), it will be picked up automatically.

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
- [datreeio/CRDs-catalog](https://github.com/datreeio/CRDs-catalog)
- [someone-stole-my-name/yaml-companion.nvim](https://github.com/someone-stole-my-name/yaml-companion.nvim)

---

**Happy Kubernetes YAMLing!** 🚢
