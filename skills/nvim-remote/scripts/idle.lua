-- Idle watchdog for a headless Neovim started by `nv start`.
-- Quits after NV_IDLE seconds without activity. Activity = `nv` touching
-- vim.g.nv_last_activity, or a UI being attached. Never quits with unsaved
-- changes — it waits until they're saved or discarded.

vim.g.nv_managed = true
vim.g.nv_owner_session = vim.env.NV_SESSION
vim.g.nv_idle_secs = math.max(tonumber(vim.env.NV_IDLE or '') or 900, 10)
vim.g.nv_last_activity = vim.uv.now()

local function has_unsaved()
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local bt = vim.bo[b].buftype
    if vim.bo[b].modified and (bt == '' or bt == 'acwrite') then return true end
  end
  return false
end

local interval = math.min(30, vim.g.nv_idle_secs) * 1000
local timer = vim.uv.new_timer()
timer:start(interval, interval, vim.schedule_wrap(function()
  if #vim.api.nvim_list_uis() > 0 then
    vim.g.nv_last_activity = vim.uv.now()
    return
  end
  local idle = (vim.uv.now() - vim.g.nv_last_activity) / 1000
  if idle >= vim.g.nv_idle_secs and not has_unsaved() then
    -- qall can still fail (e.g. a running terminal job); fall back to qall!
    -- only for scratch/terminal buffers, which has_unsaved() doesn't count.
    if not pcall(vim.cmd, 'qall') then
      pcall(vim.cmd, 'qall!')
    end
  end
end))
