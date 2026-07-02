return {
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "│" },
				change = { text = "│" },
				delete = { text = "_" },
				topdelete = { text = "‾" },
				changedelete = { text = "~" },
			},
			on_attach = function(bufnr)
				local gs = require("gitsigns")
				local map = vim.keymap.set
				local opts = { buffer = bufnr }

				map("n", "]h", gs.next_hunk, vim.tbl_extend("force", opts, { desc = "Next git hunk" }))
				map("n", "[h", gs.prev_hunk, vim.tbl_extend("force", opts, { desc = "Previous git hunk" }))
				map("n", "<leader>hs", gs.stage_hunk, vim.tbl_extend("force", opts, { desc = "Stage hunk" }))
				map("n", "<leader>hr", gs.reset_hunk, vim.tbl_extend("force", opts, { desc = "Reset hunk" }))
				map("n", "<leader>hp", gs.preview_hunk, vim.tbl_extend("force", opts, { desc = "Preview hunk" }))
				map(
					"n",
					"<leader>hb",
					function()
						gs.blame_line({ full = true })
					end,
					vim.tbl_extend("force", opts, { desc = "Blame line" })
				)
			end,
		},
	},
	{
		-- Lazygit in a floating terminal
		"akinsho/toggleterm.nvim",
		version = "*",
		keys = {
			{
				"<C-g>",
				"<cmd>lua _LAZYGIT_TOGGLE()<cr>",
				desc = "Toggle lazygit",
			},
		},
		opts = {
			open_mapping = nil,
			direction = "float",
			float_opts = { border = "curved" },
		},
		config = function(_, opts)
			require("toggleterm").setup(opts)
			local Terminal = require("toggleterm.terminal").Terminal
			local lazygit = Terminal:new({
				cmd = "lazygit",
				hidden = true,
				direction = "float",
				float_opts = { border = "curved" },
			})
			function _LAZYGIT_TOGGLE()
				lazygit:toggle()
			end
		end,
	},
}
