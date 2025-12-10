package generator

// FileMappings maps template paths to their destination paths relative to home directory.
// Templates with .tmpl extension will have the extension stripped in the output.
var FileMappings = map[string]string{
	// Zsh configuration
	"templates/zsh/.zshrc.tmpl":      ".zshrc",
	"templates/zsh/aliases.zsh.tmpl": ".config/zsh/aliases.zsh",

	// Zellij terminal multiplexer
	"templates/zellij/config.kdl.tmpl": ".config/zellij/config.kdl",

	// Neovim configuration
	"templates/nvim/init.lua":           ".config/nvim/init.lua",
	"templates/nvim/lua/plugins.lua":    ".config/nvim/lua/plugins.lua",
	"templates/nvim/lua/keymaps.lua":    ".config/nvim/lua/keymaps.lua",
	"templates/nvim/lua/options.lua":    ".config/nvim/lua/options.lua",

	// Git configuration
	"templates/git/.gitconfig.tmpl": ".gitconfig",
}
