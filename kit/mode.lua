-- kit/mode.lua: the bar at the bottom of each window says which mode you
-- are in, in words on a color: NORMAL blue, INSERT green, VISUAL / V-LINE
-- mauve, REPLACE red, PENDING peach (d, c, y waiting for a motion). Then
-- the file, [+] while it has changes not saved yet, and Ln / Col on the
-- right. Keys vis is still waiting on (Space o ...) show on the right in
-- words. Other windows show just their file, so the colored block also
-- marks the window you are in. No plugin: one function that reads state.
local leader = require('kit/leader')

local M = {}

local P, MODES
M.title = nil      -- optional function(win) -> a name for windows without one
M.on_status = nil  -- optional function(win, focused), called on every draw (the autosave hooks in here)

-- the focused bar's style: vis >= 0.9 keeps styles per window, newer builds
-- keep them on vis.ui. Both are tried.
local function focused_style(win, style)
  local ui = vis.ui
  if ui and type(ui.style_define) == 'function' and ui.style_ids then
    ui:style_define(ui.style_ids.STATUS_FOCUSED, style)
  elseif type(win.style_define) == 'function' and win.STYLE_STATUS_FOCUSED then
    win:style_define(win.STYLE_STATUS_FOCUSED, style)
  end
end

local function status(win)
  local file = win.file
  if not file then return true end
  local focused = vis.win == win
  local left, right = {}, {}
  if focused then
    local m = MODES[vis.mode] or MODES[vis.modes.NORMAL]
    left[#left + 1] = m[1]
    focused_style(win, 'back:' .. m[2] .. ',fore:' .. P.base .. ',bold')
  end
  local name = (M.title and M.title(win)) or file.name or '[No Name]'
  left[#left + 1] = name .. (file.modified and ' [+]' or '') .. (vis.recording and ' @rec' or '')
  if focused then
    local pending = vis.input_queue
    if pending and pending ~= '' and not leader.prompting then
      right[#right + 1] = leader.pretty(pending) .. ' …'
    elseif vis.count then
      right[#right + 1] = tostring(vis.count)
    end
  end
  if #win.selections > 1 then
    right[#right + 1] = win.selection.number .. '/' .. #win.selections
  end
  local sel = win.selection
  if sel then right[#right + 1] = 'Ln ' .. sel.line .. ', Col ' .. sel.col end
  win:status(' ' .. table.concat(left, '  ') .. ' ', ' ' .. table.concat(right, '  ') .. ' ')
  if M.on_status then M.on_status(win, focused) end
  return true -- vis's own bar is skipped
end

function M.setup(palette)
  P = palette
  MODES = {
    [vis.modes.NORMAL] = { 'NORMAL', P.blue },
    [vis.modes.OPERATOR_PENDING] = { 'PENDING', P.peach },
    [vis.modes.INSERT] = { 'INSERT', P.green },
    [vis.modes.REPLACE] = { 'REPLACE', P.red },
    [vis.modes.VISUAL] = { 'VISUAL', P.mauve },
    [vis.modes.VISUAL_LINE] = { 'V-LINE', P.mauve },
  }
  vis.events.subscribe(vis.events.WIN_STATUS, status, 1)
end

return M
