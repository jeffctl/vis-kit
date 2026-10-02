-- kit/cheat.lua: the cheat sheet. Space ? lists every key with what it does
-- and narrows as you type (vis-menu, the picker vis ships; without it the
-- panel opens instead). Space K keeps the same list open at the side; q
-- closes it. The rows come from the key trees in visrc.lua, so a key added
-- there shows up here. :help is vis's own, longer list.
local util = require('kit/util')
local leader = require('kit/leader')

local M = {}

M.path = util.cache_dir() .. '/keys.txt'
M.trees = {}   -- { root, label } pairs, registered by visrc.lua
M.static = {}  -- rows { group = , keys = , help = } for keys outside the trees

function M.rows()
  local rows = {}
  for _, r in ipairs(M.static) do rows[#rows + 1] = r end
  for _, t in ipairs(M.trees) do
    for _, r in ipairs(leader.rows(t[1], t[2])) do rows[#rows + 1] = r end
  end
  return rows
end

function M.lines()
  local order, groups = {}, {}
  for _, r in ipairs(M.rows()) do
    local g = r.group or 'other'
    if not groups[g] then
      groups[g] = {}
      order[#order + 1] = g
    end
    table.insert(groups[g], r)
  end
  local out = {
    '',
    '   vis keys (leader = Space)',
    '   "Space o a" = Space, o, a in turn.',
    '   Space ? finds a key. q closes this.',
  }
  for _, g in ipairs(order) do
    out[#out + 1] = ''
    out[#out + 1] = '  ' .. g:upper()
    for _, r in ipairs(groups[g]) do
      out[#out + 1] = ('  %-20s %s'):format(r.keys, r.help)
    end
  end
  out[#out + 1] = ''
  return out
end

function M.is_panel(win)
  local path = win and win.file and win.file.path
  return path ~= nil and (path == M.path or path:match('/vis%-kit/keys%.txt$') ~= nil)
end

function M.toggle()
  for win in vis:windows() do
    if M.is_panel(win) then
      win:close(true)
      return
    end
  end
  util.write_lines(M.path, M.lines())
  vis:command('vsplit ' .. util.cmd_escape(M.path))
  -- a split inherits the file window's options after it opens; set ours now
  local w = vis.win
  if M.is_panel(w) then
    util.wopt(w, 'numbers', false)
    util.wopt(w, 'relativenumbers', false)
  end
end

-- the panel's own keys
function M.install(win)
  local N = vis.modes.NORMAL
  win:map(N, 'q', function() win:close(true) end, 'Close the keys panel')
  win:map(N, '<Escape>', function() win:close(true) end, 'Close the keys panel')
end

local has_menu
function M.menu_available()
  if has_menu == nil then has_menu = util.have('vis-menu') end
  return has_menu
end

-- Space ?: type to narrow; Enter or Esc closes, nothing runs
function M.find()
  if not M.menu_available() then
    M.toggle()
    return
  end
  local text = {}
  for _, r in ipairs(M.rows()) do
    text[#text + 1] = ('%-12s %-24s %s'):format(r.group or '', r.keys, r.help)
  end
  local chosen = util.menu(text, 'key> ')
  if chosen then vis:info(chosen) end
end

return M
