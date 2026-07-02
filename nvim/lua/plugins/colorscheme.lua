-- Nord, matching the palette in ~/.config/colors/colors.css (nvim can't
-- read CSS, so this plugin is the nvim-side mirror of that source of truth).
return {
	"gbprod/nord.nvim",
	lazy = false,
	priority = 1000,
	opts = {
		terminal_colors = true,
		diff = { mode = "fg" },
	},
	config = function(_, opts)
		require("nord").setup(opts)
		vim.cmd.colorscheme("nord")
	end,
}
