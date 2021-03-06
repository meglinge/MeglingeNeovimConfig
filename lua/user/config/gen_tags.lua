-- Ctrl+\ c    Find functions calling this function
-- Ctrl+\ d    Find functions called by this function
-- Ctrl+\ e    Find this egrep pattern
-- Ctrl+\ f    Find this file
-- Ctrl+\ g    Find this definition
-- Ctrl+\ i    Find files #including this file
-- Ctrl+\ s    Find this C symbol
-- Ctrl+\ t    Find this text strin
local M = {}
M.setup = function()
  local binPath = vim.fn.stdpath('config') .. '/lua/user/bin'
  vim.cmd(
    [[
      let g:loaded_gentags#ctags = 1
      let g:gen_tags#gtags_default_map = 1
      let g:gen_tags#gtags_bin=']] .. binPath ..[[/gtags'
      let g:gen_tags#global_bin=']] ..binPath..[[/global'
      let g:gen_tags#ctags_opts='-c --verbose'
      let g:gen_tags#gtags_auto_gen=1
      let g:gen_tags#verbose=0
    ]]
    )
end
M.setup()


