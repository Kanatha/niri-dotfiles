return {
	{
		-- Installs the standalone formatter/linter binaries that
		-- mason-lspconfig doesn't manage (it only handles LSP servers).
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			ensure_installed = {
				"stylua", -- Lua formatter
				"php-cs-fixer", -- PHP formatter
				"prettier", -- JS/HTML formatter
				"selene", -- Lua linter
			},
		},
	},
	{
		"stevearc/conform.nvim",
		event = { "BufWritePre" },
		cmd = "ConformInfo",
		keys = {
			{
				"<leader>cf",
				function()
					require("conform").format({ async = true, lsp_fallback = true })
				end,
				mode = { "n", "v" },
				desc = "Format buffer",
			},
		},
		opts = {
			formatters_by_ft = {
				lua = { "stylua" },
				php = { "php_cs_fixer" },
				javascript = { "prettier" },
				javascriptreact = { "prettier" },
				html = { "prettier" },
				json = { "prettier" },
				css = { "prettier" },
			},
			format_on_save = {
				timeout_ms = 1500,
				lsp_fallback = true,
			},
		},
	},
	{
		"mfussenegger/nvim-lint",
		event = { "BufWritePost", "BufReadPost", "InsertLeave" },
		config = function()
			local lint = require("lint")
			-- Only Lua for now: it's a standalone linter that needs no
			-- project config. eslint/phpstan need a project-level config
			-- file to be useful, so they're left out until you have one
			-- (easy to add later: lint.linters_by_ft.javascript = { "eslint_d" }).
			lint.linters_by_ft = {
				lua = { "selene" },
			}
			vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
				callback = function()
					lint.try_lint()
				end,
			})
		end,
	},
}
