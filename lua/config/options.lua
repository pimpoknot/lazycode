-- Options are automatically loaded before lazy.nvim startup
-- Default options that are always set: https://github.com/LazyVim/LazyVim/blob/main/lua/lazyvim/config/options.lua
-- Add any additional options here

-- LazyCode: VS Code behavior
vim.g.lazycode = true
vim.o.mouse = "a"
vim.o.mousemodel = "popup_setpos"
vim.o.clipboard = "unnamedplus"
vim.o.timeoutlen = 400
-- No command line row and no "Press ENTER" prompts, like an IDE. Messages stay in :messages.
vim.o.cmdheight = 0
vim.o.messagesopt = "wait:0,history:500"
-- Blinks like VS Code. The LazyCode window fades it in and out.
local blink = "-blinkwait500-blinkon530-blinkoff530"
vim.o.guicursor = "n-v-c-sm:block" .. blink .. ",i-ci-ve:ver25" .. blink .. ",r-cr-o:hor20,t:block-TermCursor"
local lg = vim.fn.stdpath("config") .. "/assets/lazygit.yml"
vim.env.LG_CONFIG_FILE = lg

vim.api.nvim_create_user_command("LazyCodeInstallTools", function()
  require("lazycode.languages").install_tools()
end, { desc = "Install the default language servers" })
vim.api.nvim_create_user_command("LazyCodeReload", function()
  require("lazycode.project").reload()
end, { desc = "Reload Window" })
vim.api.nvim_create_user_command("LazyCodeLanguage", function(args)
  require("lazycode.languages").enable(args.args ~= "" and args.args or vim.bo.filetype)
end, { nargs = "?", desc = "Enable completion for another language" })
