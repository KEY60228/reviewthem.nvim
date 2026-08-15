if vim.fn.has("nvim-0.10.0") == 0 then
  vim.api.nvim_err_writeln("reviewthem.nvim requires at least nvim-0.10.0")
  return
end

if vim.g.loaded_reviewthem == 1 then
  return
end
math.randomseed(os.clock() * 1000 + vim.uv.hrtime() % 1000000)
vim.g.loaded_reviewthem = 1
