
-- Set 'compiler' globally (could instead have a different local setting per filetype)
vim.cmd('compiler! jai')
-- Append some stuff to default makeprg options
-- vim.opt.makeprg:append(' -import_dir ' .. vim.env.DEV_HOME .. '/bin/jai_modules -')
vim.opt.makeprg = 'build.bat'

-- For some reason using just ':p' is not showing the correct filename
print('Loaded ' .. vim.fn.fnamemodify(debug.getinfo(1).source:sub(2), ":p:h") .. '\\.nvim.lua')
