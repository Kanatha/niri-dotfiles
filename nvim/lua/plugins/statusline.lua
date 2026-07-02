return {
	"nvim-lualine/lualine.nvim",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	event = "VeryLazy",
	opts = {
		options = {
			theme = "nord",
			globalstatus = true,
			icons_enabled = true,
		},
		sections = {
			lualine_c = { { "filename", path = 1 } },
		},
	},
}
