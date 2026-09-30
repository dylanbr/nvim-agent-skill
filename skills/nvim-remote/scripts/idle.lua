-- Idle watchdog for a headless Neovim started by `nv start`, which runs
-- start(). Quits after NV_IDLE seconds (validated by nv) without activity.
-- Activity = `nv` touching vim.g.nv_last_activity, or a UI being attached.
-- Never quits with unsaved changes — it waits until they're saved or discarded.
-- `nv stop` uses unsaved() too, so both apply the same rule.
local M = {}

-- Number of modified file buffers (terminal and scratch buffers don't count).
function M.unsaved()
  local n = 0
  for _, b in ipairs(vim.api.nvim_list_bufs()) do
    local bt = vim.bo[b].buftype
    if vim.bo[b].modified and (bt == '' or bt == 'acwrite') then n = n + 1 end
  end
  return n
end

function M.start()
  vim.g.nv_idle_secs = tonumber(vim.env.NV_IDLE)
  vim.g.nv_last_activity = vim.uv.now()
  local interval = math.min(30, vim.g.nv_idle_secs) * 1000
  local timer = vim.uv.new_timer()
  timer:start(interval, interval, vim.schedule_wrap(function()
    if #vim.api.nvim_list_uis() > 0 then
      vim.g.nv_last_activity = vim.uv.now()
      return
    end
    local idle = (vim.uv.now() - vim.g.nv_last_activity) / 1000
    if idle >= vim.g.nv_idle_secs and M.unsaved() == 0 then
      -- qall can still fail (e.g. a running terminal job); fall back to qall!
      -- only for scratch/terminal buffers, which unsaved() doesn't count.
      if not pcall(vim.cmd, 'qall') then
        pcall(vim.cmd, 'qall!')
      end
    end
  end))
end

return M
