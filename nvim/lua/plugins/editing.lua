return {
	{
		"echasnovski/mini.surround",
		version = "*",
		event = "VeryLazy",
		opts = {},
	},
	{
		"echasnovski/mini.pairs",
		version = "*",
		event = "InsertEnter",
		opts = {},
	},
	{
		-- Popup showing available keybindings as you type a prefix
		-- (e.g. press <leader> and wait) — helpful discoverability net
		-- for all the custom keymaps in this config.
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			preset = "helix",
		},
	},
}
