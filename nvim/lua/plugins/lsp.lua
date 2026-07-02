return {
	{
		"mason-org/mason.nvim",
		opts = {},
	},
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			"mason-org/mason.nvim",
			"neovim/nvim-lspconfig",
		},
		opts = {
			-- Neovim 0.11+: automatic_enable calls vim.lsp.enable() for
			-- every installed server, replacing the old manual
			-- lspconfig.<server>.setup() "framework" (deprecated, removed
			-- in nvim-lspconfig v3.0.0).
			--
			-- stylua excluded: it's a formatter, but nvim-lspconfig ships
			-- an "lsp/stylua.lua" default for its `--lsp` mode, and mason
			-- installed it (for conform.nvim, as a plain CLI formatter).
			-- Auto-enabling it too would attach a second, redundant
			-- Lua client alongside lua_ls.
			automatic_enable = { exclude = { "stylua" } },
			ensure_installed = {
				"lua_ls", -- Lua
				"intelephense", -- PHP
				"ts_ls", -- JavaScript
				"html", -- HTML
			},
			automatic_installation = true,
		},
	},
	{
		"neovim/nvim-lspconfig",
		dependencies = { "saghen/blink.cmp" },
		event = { "BufReadPre", "BufNewFile" },
		config = function()
			-- Apply blink.cmp's capabilities to every server (nvim-lspconfig
			-- provides the base configs on the 'lsp/' runtimepath; this
			-- merges in on top of them).
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})

			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						diagnostics = { globals = { "vim" } },
						workspace = { checkThirdParty = false },
					},
				},
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				desc = "LSP keymaps",
				callback = function(args)
					local opts = { buffer = args.buf }
					local map = vim.keymap.set
					map("n", "gd", vim.lsp.buf.definition, vim.tbl_extend("force", opts, { desc = "Goto definition" }))
					map("n", "gr", vim.lsp.buf.references, vim.tbl_extend("force", opts, { desc = "Goto references" }))
					map(
						"n",
						"gI",
						vim.lsp.buf.implementation,
						vim.tbl_extend("force", opts, { desc = "Goto implementation" })
					)
					map("n", "K", vim.lsp.buf.hover, vim.tbl_extend("force", opts, { desc = "Hover docs" }))
					map(
						"n",
						"<leader>rn",
						vim.lsp.buf.rename,
						vim.tbl_extend("force", opts, { desc = "Rename symbol" })
					)
					map(
						{ "n", "v" },
						"<leader>ca",
						vim.lsp.buf.code_action,
						vim.tbl_extend("force", opts, { desc = "Code action" })
					)
					map(
						"n",
						"<leader>d",
						vim.diagnostic.open_float,
						vim.tbl_extend("force", opts, { desc = "Line diagnostics" })
					)
					map(
						"n",
						"]d",
						function()
							vim.diagnostic.jump({ count = 1, float = true })
						end,
						vim.tbl_extend("force", opts, { desc = "Next diagnostic" })
					)
					map(
						"n",
						"[d",
						function()
							vim.diagnostic.jump({ count = -1, float = true })
						end,
						vim.tbl_extend("force", opts, { desc = "Previous diagnostic" })
					)
				end,
			})
		end,
	},
}
