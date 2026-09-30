-- Safe edits to a buffer the user has open, for `nv buf read|edit|save`.
-- Every function returns text whose first word is the status, which nv maps to
-- an exit code: ok, not-open, stop (tell the user), changed (re-read and retry).
local api = vim.api
local M = {}

-- Buffer number for PATH if it's loaded, else nil. Symlinked paths match too.
local function find(path)
  if vim.fn.bufloaded(path) == 0 then return nil end
  return vim.fn.bufnr(path)
end

-- Run :checktime on BUF; returns the warning it gave, if any (W11 changed on
-- disk but not reloaded, W12 changed on disk and in the buffer, W13 created,
-- W16 permissions changed, E211 deleted).
local function checktime(buf)
  vim.v.warningmsg = ''
  api.nvim_buf_call(buf, function() vim.cmd('checktime') end)
  return vim.v.warningmsg
end

local function header(buf)
  return string.format('buf=%d tick=%d modified=%s lines=%d',
    buf, vim.b[buf].changedtick, tostring(vim.bo[buf].modified), api.nvim_buf_line_count(buf))
end

-- Find PATH's buffer and run checktime on it: the buffer, or nil and the status text.
local function open(path)
  local buf = find(path)
  if not buf then return nil, 'not-open ' .. path end
  local warning = checktime(buf)
  if warning ~= '' then return nil, 'stop ' .. warning end
  return buf
end

-- Re-check a buffer before changing it: as open(), and also unchanged since TICK.
local function recheck(path, tick)
  local buf, err = open(path)
  if not buf then return nil, err end
  if vim.b[buf].changedtick ~= tick then
    return nil, 'changed the buffer changed since it was read (now ' .. header(buf) .. '); re-read it'
  end
  return buf
end

-- With 'autoread' off, checktime warns only once, so a buffer can be stale
-- without a warning. Compare it with the file before saving.
local function stale(buf)
  local autoread = api.nvim_get_option_value('autoread', { buf = buf })
  if autoread == nil then autoread = vim.go.autoread end
  if autoread then return false end
  local name = api.nvim_buf_get_name(buf)
  if vim.fn.filereadable(name) == 0 then return true end
  return not vim.deep_equal(api.nvim_buf_get_lines(buf, 0, -1, false), vim.fn.readfile(name))
end

local function write(buf)
  api.nvim_buf_call(buf, function() vim.cmd('silent write') end)
end

-- Lines A..B (1-based, inclusive; default whole buffer), numbered, after a header.
function M.read(path, a, b)
  local buf, err = open(path)
  if not buf then return err end
  local n = api.nvim_buf_line_count(buf)
  a = math.max(a or 1, 1)
  b = math.min(b or n, n)
  local out = { 'ok ' .. header(buf) }
  for i, l in ipairs(api.nvim_buf_get_lines(buf, a - 1, b, false)) do
    out[#out + 1] = string.format('%6d  %s', a + i - 1, l)
  end
  return table.concat(out, '\n')
end

-- Replace lines A..B (1-based, inclusive) with the lines in TEXTFILE. B = A - 1
-- inserts before line A; no TEXTFILE deletes. SAVE writes the buffer afterwards,
-- and is refused when the buffer has unsaved changes, since that would save the
-- user's work.
function M.edit(path, tick, a, b, textfile, save)
  local buf, err = recheck(path, tick)
  if not buf then return err end
  if save and vim.bo[buf].modified then
    return 'stop the buffer has unsaved changes; not editing (edit without saving, or save it first)'
  end
  if save and stale(buf) then
    return 'stop the buffer differs from the file on disk; not editing'
  end
  local n = api.nvim_buf_line_count(buf)
  if a < 1 or a > n + 1 or b < a - 1 or b > n then
    return string.format('stop lines %d..%d are outside the buffer (1..%d)', a, b, n)
  end
  local lines = textfile and vim.fn.readfile(textfile) or {}
  -- Separate calls to a buffer that isn't current would merge into one undo
  -- block. Setting 'undolevels' to itself starts a new one.
  api.nvim_buf_call(buf, function() vim.cmd('let &undolevels = &undolevels') end)
  api.nvim_buf_set_lines(buf, a - 1, b, false, lines)
  if save then write(buf) end
  return 'ok ' .. header(buf) .. (save and ' saved' or ' unsaved')
end

-- Save the user's unsaved changes as they are (option 3's first step).
function M.save(path, tick)
  local buf, err = recheck(path, tick)
  if not buf then return err end
  write(buf)
  return 'ok ' .. header(buf) .. ' saved'
end

return M
