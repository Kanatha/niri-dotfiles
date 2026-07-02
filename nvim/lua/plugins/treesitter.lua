return {
	{
		"nvim-treesitter/nvim-treesitter",
		-- Pinned to the stable legacy API ("main" is a recent rewrite that
		-- dropped `nvim-treesitter.configs`, which this file and the
		-- textobjects plugin below still depend on).
		branch = "master",
		build = ":TSUpdate",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = {
			"nvim-treesitter/nvim-treesitter-textobjects",
			"JoosepAlviste/nvim-ts-context-commentstring",
		},
		config = function()
			require("nvim-treesitter.configs").setup({
				-- Baseline parsers for nvim's own config/docs, plus the
				-- languages picked for this setup: Lua, PHP, JS, HTML
				ensure_installed = {
					"lua",
					"vim",
					"vimdoc",
					"query",
					"bash",
					"markdown",
					"markdown_inline",
					"php",
					"javascript",
					"html",
					"css",
					"json",
				},
				auto_install = true,
				highlight = { enable = true },
				indent = { enable = true },
				-- Adds text objects usable with normal vim operators (d/c/y),
				-- e.g. `daf` deletes a function, `cif` changes inside it.
				-- Default vim motions are untouched; this only adds new
				-- text-object targets.
				textobjects = {
					select = {
						enable = true,
						lookahead = true,
						keymaps = {
							["af"] = "@function.outer",
							["if"] = "@function.inner",
							["ac"] = "@class.outer",
							["ic"] = "@class.inner",
							["aa"] = "@parameter.outer",
							["ia"] = "@parameter.inner",
						},
					},
					move = {
						enable = true,
						goto_next_start = { ["]f"] = "@function.outer", ["]c"] = "@class.outer" },
						goto_previous_start = { ["[f"] = "@function.outer", ["[c"] = "@class.outer" },
					},
				},
			})
			require("ts_context_commentstring").setup({ enable_autocmd = false })
		end,
	},
}
