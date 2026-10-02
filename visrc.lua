-- ============================================================================
--  vis kit: the Neovim kit's keys and agenda, on vis (https://github.com/martanne/vis).
--  Space is the leader and never times out; a pause shows what can come next.
--  Space ? finds a key. A plain launch opens your day. Files save themselves.
--
--  Put this folder at ~/.config/vis (or run vis with VIS_PATH pointing here).
--  Needs vis 0.9 or newer with Lua and LPeg. vis-menu (ships with vis) powers
--  the pickers; without it the panel versions open instead.
-- ============================================================================
require('vis')

local util = require('kit/util')
local leader = require('kit/leader')
local org = require('kit/org')
local agenda = require('kit/agenda')
local cheat = require('kit/cheat')
local mode = require('kit/mode')

local N, I, V, VL = vis.modes.NORMAL, vis.modes.INSERT, vis.modes.VISUAL, vis.modes.VISUAL_LINE

-- Catppuccin Mocha, the few colors the mode bar needs (themes/catppuccin-mocha.lua has the rest)
local P = {
  base = '#1e1e2e', blue = '#89b4fa', green = '#a6e3a1', mauve = '#cba6f7',
  red = '#f38ba8', peach = '#fab387', teal = '#94e2d5',
}

-- .org files and the agenda get their lexers (lexers/org.lua, lexers/orgagenda.lua)
if vis.ftdetect and vis.ftdetect.filetypes then
  vis.ftdetect.filetypes.org = { ext = { '%.org$', '%.org_archive$' } }
  vis.ftdetect.filetypes.orgagenda = { ext = { '%.orgagenda$' } }
end

local function is_org(win)
  local name = win.file and win.file.name
  return win.syntax == 'org' or (name ~= nil and name:match('%.org$') ~= nil)
end

local function feed(keys)
  return function() vis:feedkeys(keys) end
end

-- ============================================================================
--  AUTOSAVE, like VS Code's: a changed file is written when you leave insert
--  mode (Esc, Ctrl c), and in normal mode right after any change. Only real
--  files, never the agenda or the keys panel. A save that fails says so once;
--  Ctrl s tries again. Undo history stays (u / Ctrl r), so a save is never final.
-- ============================================================================
local failed = {}

local function autosave(win)
  local file = win and win.file
  if not file or not file.path or not file.modified or failed[file.path] then return end
  if agenda.is_agenda(win) or cheat.is_panel(win) then return end
  if not util.save(win) then
    failed[file.path] = true
    vis:info('Not saved: ' .. (file.name or file.path) .. '  (Ctrl s tries again)')
  end
end

local function save_now()
  local file = vis.win and vis.win.file
  if not file then return end
  if file.path then failed[file.path] = nil end
  if not file.path then vis:info('No file name yet: type :w name') return end
  if util.save(vis.win) then vis:info('Saved ' .. (file.name or file.path)) end
end

vis:map(N, '<C-s>', save_now, 'Save now')
vis:map(I, '<C-s>', save_now, 'Save now')

mode.on_status = function(win, focused)
  if focused and vis.mode == N and vis.input_queue == '' and not vis.recording then autosave(win) end
end

-- ============================================================================
--  EDITING KEYS (the VS Code habits the Neovim kit kept)
-- ============================================================================
-- centered scrolling and search
vis:map(N, '<C-d>', '<vis-window-halfpage-down><vis-window-redraw-center>', 'Half a page down, centered')
vis:map(N, '<C-u>', '<vis-window-halfpage-up><vis-window-redraw-center>', 'Half a page up, centered')
vis:map(N, '<S-Down>', '<vis-window-halfpage-down><vis-window-redraw-center>', 'Half a page down')
vis:map(N, '<S-Up>', '<vis-window-halfpage-up><vis-window-redraw-center>', 'Half a page up')
vis:map(N, 'n', '<vis-motion-search-repeat-forward><vis-window-redraw-center>', 'Next match, centered')
vis:map(N, 'N', '<vis-motion-search-repeat-backward><vis-window-redraw-center>', 'Previous match, centered')

-- x deletes a letter without copying it
vis:map(N, 'x', '"_<vis-delete-char-next>', 'Delete a letter (not copied)')

-- between splits: Ctrl j / Ctrl k, or Space then an arrow
vis:map(N, '<C-j>', '<C-w>j', 'Next split')
vis:map(N, '<C-k>', '<C-w>k', 'Previous split')

-- stamps while typing: Alt t a full ISO time stamp, Alt w the ISO week (W39)
vis:map(I, '<M-t>', function() vis:insert(org.iso_now()) end, 'Insert an ISO time stamp')
vis:map(I, '<M-w>', function() vis:insert(org.iso_week()) end, 'Insert this week, like W39')

-- Alt Up / Alt Down move the line you are on (also while typing); in a
-- selection J / K and Alt Up / Down move the selected lines
local function move_line(dir)
  return function()
    local win = vis.win
    local file = win.file
    local n, col = win.selection.line, win.selection.col
    local target = n + dir
    if target < 1 or target > #file.lines then return end
    local a, b = file.lines[n], file.lines[target]
    file.lines[n] = b
    file.lines[target] = a
    win.selection:to(target, col)
    if vis.mode == N then util.save(win) end
  end
end

local function move_selection(dir)
  return function()
    local win = vis.win
    local file = win.file
    local sel = win.selection
    local r = sel.range
    if not r then return end
    local first = util.line_of(file, r.start)
    local last = util.line_of(file, math.max(r.start, r.finish - 1))
    local lines = util.file_lines(file)
    if (dir < 0 and first <= 1) or (dir > 0 and last >= #lines) then return end
    local block = {}
    for i = first, last do block[#block + 1] = lines[i] end
    if dir < 0 then
      block[#block + 1] = lines[first - 1]
      util.splice(file, first - 1, last, block)
      first, last = first - 1, last - 1
    else
      table.insert(block, 1, lines[last + 1])
      util.splice(file, first, last + 1, block)
      first, last = first + 1, last + 1
    end
    sel.range = { start = util.line_offset(file, first), finish = util.line_offset(file, last + 1) }
  end
end

vis:map(N, '<M-Up>', move_line(-1), 'Move this line up')
vis:map(N, '<M-Down>', move_line(1), 'Move this line down')
vis:map(I, '<M-Up>', move_line(-1), 'Move this line up')
vis:map(I, '<M-Down>', move_line(1), 'Move this line down')
for _, m in ipairs({ V, VL }) do
  vis:map(m, '<M-Up>', move_selection(-1), 'Move the selected lines up')
  vis:map(m, '<M-Down>', move_selection(1), 'Move the selected lines down')
  vis:map(m, 'K', move_selection(-1), 'Move the selected lines up')
  vis:map(m, 'J', move_selection(1), 'Move the selected lines down')
end

-- ============================================================================
--  PICKERS: vis-menu (ships with vis) over a list; nil when nothing was picked
-- ============================================================================
local function pick(list, prompt)
  if #list == 0 then vis:info('Nothing to pick from') return nil end
  if not cheat.menu_available() then vis:info('vis-menu is not installed: type :e path instead') return nil end
  return util.menu(list, prompt)
end

-- open a file in this window; in a new one when this window will not let go
local function edit(path)
  if not vis:command('e ' .. util.cmd_escape(path)) then vis:command('open ' .. util.cmd_escape(path)) end
end

local function split_lines(text)
  local out = {}
  for line in (text or ''):gmatch('[^\n]+') do out[#out + 1] = line end
  return out
end

local function find_file()
  local list = split_lines(util.sh('find . -type f ! -path "*/.*" | sed "s|^\\./||" | sort | head -5000'))
  local choice = pick(list, 'file> ')
  if choice then edit(choice) end
end

local function find_org()
  local dir = util.org_dir()
  local list = {}
  for _, p in ipairs(util.org_files(dir)) do list[#list + 1] = util.relative(p, dir) end
  local choice = pick(list, 'org> ')
  if choice then edit(dir .. '/' .. choice) end
end

local recent_path = util.cache_dir() .. '/recent'

local function remember(win)
  local path = win.file and win.file.path
  if not path or agenda.is_agenda(win) or cheat.is_panel(win) then return end
  local out = { path }
  for _, p in ipairs(util.read_lines(recent_path) or {}) do
    if p ~= path and #out < 40 then out[#out + 1] = p end
  end
  util.write_lines(recent_path, out)
end

local function recent()
  local list = {}
  for _, p in ipairs(util.read_lines(recent_path) or {}) do
    if util.exists(p) then list[#list + 1] = p end
  end
  local choice = pick(list, 'recent> ')
  if choice then edit(choice) end
end

local function switch_window()
  local names, wins = {}, {}
  for w in vis:windows() do
    local name = w.file and (w.file.name or '[No Name]') or '?'
    if agenda.is_agenda(w) then name = 'agenda' elseif cheat.is_panel(w) then name = 'keys' end
    names[#names + 1] = name
    wins[name] = w
  end
  local choice = pick(names, 'window> ')
  if choice and wins[choice] then vis.win = wins[choice] end
end

local function copy_path()
  local path = vis.win.file and vis.win.file.path
  if not path then vis:info('No file name yet') return end
  local code = vis:pipe(path .. '\n', 'vis-clipboard --copy')
  vis:info(code == 0 and ('Copied ' .. path) or 'No clipboard tool found (vis-clipboard)')
end

-- ============================================================================
--  ORG KEYS: everything edits the text in place (kit/org.lua)
-- ============================================================================
-- run fn(lines, heading_line) on the task the cursor is in; the cursor stays put
local function with_heading(fn)
  local win = vis.win
  local line, col = win.selection.line, win.selection.col
  local ok = org.apply(win, function(lines, cur)
    local h = org.heading_above(lines, cur)
    if not h then return false end
    return fn(lines, h)
  end)
  if ok == false then
    vis:info('Not on a task: put the cursor on a heading or under one')
    return false
  end
  win.selection:to(line, col)
  util.save(win)
  return true
end

local function set_state(kw)
  if with_heading(function(lines, h) org.set_state(lines, h, kw) end) then
    vis:info(kw == '' and 'State cleared' or ('State: ' .. kw))
  end
end

local function set_date(key)
  return function(text)
    local t, time = org.parse_date(text)
    if not t then vis:info(time) return end
    local stamp = org.stamp(t, true, time)
    if with_heading(function(lines, h) org.set_planning(lines, h, key, stamp) end) then
      vis:info(key .. ': ' .. stamp)
    end
  end
end

local function tick()
  local win = vis.win
  local line, col = win.selection.line, win.selection.col
  local ok = org.apply(win, function(lines, cur)
    local t = org.tick(lines[cur])
    if not t then return false end
    lines[cur] = t
  end)
  if ok == false then
    vis:info('No list item here. A checkbox is a line like:  - [ ] text')
    return
  end
  win.selection:to(line, col)
  util.save(win)
end

-- a new line below with the same shape as this one: a heading at the same
-- level (after the task's text), a list item (with a box when this one has
-- one), the next number, else a plain line. `kw` makes it a task.
local function new_below(kw)
  return function()
    local win = vis.win
    local file = win.file
    local n = win.selection.line
    local lines = util.file_lines(file)
    local line = lines[n] or ''
    local level = org.level(line)
    local prefix, at = '', n
    if level then
      prefix = string.rep('*', level) .. ' '
      at = org.subtree_end(lines, n)
    elseif kw then
      local h = org.heading_above(lines, n)
      prefix = string.rep('*', h and org.level(lines[h]) or 1) .. ' '
      at = h and org.subtree_end(lines, h) or n
    else
      local bullet = line:match('^(%s*[-+]%s+)') or line:match('^(%s+%*%s+)')
      local indent, num, rest = line:match('^(%s*)(%d+)([.)]%s+)')
      if bullet then
        prefix = bullet .. (line:sub(#bullet + 1):match('^%[[ xX%-]%]%s') and '[ ] ' or '')
      elseif num then
        prefix = indent .. (tonumber(num) + 1) .. rest
      end
    end
    if kw then prefix = prefix .. kw .. ' ' end
    util.splice(file, at + 1, at, { prefix })
    win.selection:to(at + 1, #prefix + 1)
    vis.mode = I
  end
end

local function insert_stamp(text)
  local t, time = org.parse_date(text)
  if not t then vis:info(time) return end
  vis:insert(org.stamp(t, true, time))
end

local function set_property(name, value)
  if with_heading(function(lines, h) org.set_property(lines, h, name, value) end) then
    vis:info(name .. ' set to ' .. value)
  end
end

local function current_tags()
  local lines = util.file_lines(vis.win.file)
  local h = org.heading_above(lines, vis.win.selection.line)
  if not h then return '' end
  local _, _, _, _, tags = org.parse_heading(lines[h])
  return tags and tags:gsub('^:', ''):gsub(':$', '') or ''
end

local function current_word()
  local win = vis.win
  local range = win.file:text_object_word(win.selection.pos)
  if not range then return '' end
  return win.file:content(range)
end

local function replace_everywhere(word)
  return function(new)
    local function esc(s) return (s:gsub('([%^%$%(%)%%%.%[%]%*%+%-%?%|%{%}\\/])', '\\%1')) end
    if word == '' then vis:info('Put the cursor on a word first') return end
    vis:command(('x/\\<%s\\>/ c/%s/'):format(esc(word), (new:gsub('([\\/])', '\\%1'))))
    vis:info('Replaced "' .. word .. '" with "' .. new .. '" everywhere')
  end
end

local function capture(kind)
  return function(title)
    if title == '' then vis:info('Nothing captured: the title was empty') return end
    if kind == 's' or kind == 'd' then
      return leader.prompt((kind == 's' and 'Start' or 'Due') .. ' date (empty = today, +3, fri, 2026-10-05): ', '', function(text)
        local t, time = org.parse_date(text)
        if not t then vis:info(time) return end
        org.capture(kind, title, org.stamp(t, true, time))
        vis:info('Captured into inbox.org: ' .. title)
      end)
    end
    org.capture(kind, title)
    vis:info('Captured into inbox.org: ' .. title)
  end
end

local state_pick = leader.pick('State', org.state_options, set_state)

-- keys that only make sense in an org file: cit, Tab / Shift Tab between headings, << >> promote / demote
local function install_org_keys(win)
  leader.map_window(win, N, 'cit', state_pick, 'Change the state of the task (TODO, DONE, ...)')
  win:map(N, '<Tab>', function()
    local lines = util.file_lines(win.file)
    local n = org.next_heading(lines, win.selection.line)
    if n then win.selection:to(n, 1) else vis:info('No heading below') end
  end, 'Next heading')
  win:map(N, '<S-Tab>', function()
    local lines = util.file_lines(win.file)
    local n = org.prev_heading(lines, win.selection.line)
    if n then win.selection:to(n, 1) else vis:info('No heading above') end
  end, 'Previous heading')
  local function shift(dir, keys)
    return function()
      local lines = util.file_lines(win.file)
      if not org.level(lines[win.selection.line]) then vis:feedkeys(keys) return end
      with_heading(function(ls, h) return org.shift(ls, h, dir) end)
    end
  end
  win:map(N, '>>', shift(1, '<vis-operator-shift-right><vis-operator-shift-right>'), 'Demote the heading (indent elsewhere)')
  win:map(N, '<<', shift(-1, '<vis-operator-shift-left><vis-operator-shift-left>'), 'Promote the heading (outdent elsewhere)')
end

-- ============================================================================
--  SPACE: the leader. Groups wait for the next key and show what can come.
-- ============================================================================
local root = { name = 'shortcuts', keys = {
  ['?'] = { help = 'Find a key (type to narrow)', run = cheat.find },
  K = { help = 'Keys panel at the side', run = cheat.toggle },
  d = { help = 'Delete, no copy (then a motion)', run = feed('"_d') },
  x = { help = 'Tick a checkbox (adds one)', run = tick },
  r = { help = 'Replace this word everywhere', hint = 'replace word',
        prompt = function() return 'Replace "' .. current_word() .. '" with: ' end,
        default = current_word,
        apply = function(new) replace_everywhere(current_word())(new) end },
  ['<Enter>'] = { help = 'New heading / list item below', run = new_below() },
  ['<Left>'] = { help = 'Previous split', run = feed('<C-w>k'), hidden = true },
  ['<Up>'] = { help = 'Previous split', run = feed('<C-w>k'), hidden = true },
  ['<Right>'] = { help = 'Next split', run = feed('<C-w>j'), hidden = true },
  ['<Down>'] = { help = 'Next split', run = feed('<C-w>j'), hidden = true },
  e = { name = 'explorer', keys = {
    e = { help = 'Pick a file here (.. goes up)', run = function() edit('.') end },
    f = { help = "Pick from this file's folder", run = function()
      local path = vis.win.file and vis.win.file.path
      edit(path and util.dirname(path) or '.')
    end },
    o = { help = 'Pick from your org folder', run = function() edit(util.org_dir()) end },
  } },
  f = { name = 'files', keys = {
    f = { help = 'Find a file under this folder', run = find_file },
    o = { help = 'Find one of your org files', run = find_org },
    b = { help = 'Switch to an open file', run = switch_window },
    r = { help = 'Recent files', run = recent },
    p = { help = 'Copy this file path', run = copy_path },
  } },
  p = { name = 'recent', keys = {
    r = { help = 'Recent files', run = recent },
  } },
  s = { name = 'splits', keys = {
    v = { help = 'Split side by side', run = function() vis:command('vsplit') end },
    h = { help = 'Split stacked', run = function() vis:command('split') end },
    x = { help = 'Close this split', run = function() vis:command('q') end },
  } },
  c = { name = 'clipboard', keys = {
    y = { help = 'Copy line to system clipboard', run = feed('"+yy') },
    p = { help = 'Paste system clipboard after', run = feed('"+p') },
    P = { help = 'Paste system clipboard before', run = feed('"+P') },
  } },
  o = { name = 'org', keys = {
    a = { name = 'agenda', keys = {
      d = { help = 'Your day (the home screen)', run = function() agenda.show('day', 0) end },
      a = { help = 'This week, Mon to Sun', run = function() agenda.show('week', 0) end },
      t = { help = 'Every open task, file by file', run = function() agenda.show('tasks') end },
      c = { help = 'Done, newest first', run = function() agenda.show('done') end },
    } },
    c = { name = 'capture', keys = {
      t = { help = 'New task into the inbox', prompt = 'Task: ', apply = capture('t') },
      s = { help = 'New task with a start date', prompt = 'Task: ', apply = capture('s') },
      d = { help = 'New task with a due date', prompt = 'Task: ', apply = capture('d') },
      n = { help = 'New note into the inbox', prompt = 'Note: ', apply = capture('n') },
    } },
    i = { name = 'insert', keys = {
      s = { help = 'Start date (SCHEDULED)', prompt = 'Start date (empty = today, +3, fri, 2026-10-05): ', apply = set_date('SCHEDULED') },
      d = { help = 'Deadline', prompt = 'Due date (empty = today, +3, fri, 2026-10-05): ', apply = set_date('DEADLINE') },
      ['.'] = { help = 'A date here (an appointment)', prompt = 'Date (empty = today, +3, fri 10:00): ', apply = insert_stamp },
      t = { help = 'New TODO below', run = new_below('TODO') },
      h = { help = 'New heading below', run = new_below() },
    } },
    s = { help = 'Change state (TODO, DONE…)', hint = 'state', title = 'State', pick = org.state_options, apply = set_state },
    [','] = { help = 'Priority (A top, F low)', hint = 'priority', title = 'Priority', pick = org.priority_options,
              apply = function(pri)
                if with_heading(function(lines, h) return org.set_priority(lines, h, pri) end) then
                  vis:info(pri == '' and 'Priority cleared' or ('Priority ' .. pri))
                end
              end },
    t = { help = 'Set tags', prompt = 'Tags (space or : between them): ', default = current_tags,
          apply = function(text)
            if with_heading(function(lines, h) return org.set_tags(lines, h, text) end) then vis:info('Tags set') end
          end },
    p = { name = 'property', keys = {
      s = { help = 'Set START to now', run = function() set_property('START', org.stamp(os.time(), false, true)) end },
      p = { help = 'Set a property', prompt = 'Property: ', apply = function(name)
        if name == '' then return end
        return leader.prompt(name .. ': ', '', function(value) set_property(name, value) end)
      end },
    } },
  } },
} }

local vroot = { name = 'shortcuts (selecting)', keys = {
  d = { help = 'Delete selection, no copy', run = feed('"_d') },
  c = { name = 'clipboard', keys = {
    y = { help = 'Copy selection to clipboard', run = feed('"+y') },
  } },
} }

leader.map(N, '<Space>', root, 'Leader: Space, then a key (Space ? lists them)')
leader.map(V, '<Space>', vroot, 'Leader: Space, then a key')
leader.map(VL, '<Space>', vroot, 'Leader: Space, then a key')

-- ============================================================================
--  CHEAT SHEET rows for the keys outside the Space trees
-- ============================================================================
cheat.trees = { { root, 'Space' }, { vroot, 'Space (visual)' } }
cheat.static = {
  { group = 'modes (the bar at the bottom)', keys = 'NORMAL (blue)', help = 'Keys are commands' },
  { group = 'modes (the bar at the bottom)', keys = 'INSERT (green)', help = 'Typing text (i starts)' },
  { group = 'modes (the bar at the bottom)', keys = 'VISUAL (mauve)', help = 'Selecting (v / V start)' },
  { group = 'modes (the bar at the bottom)', keys = 'REPLACE (red)', help = 'Typing over text' },
  { group = 'modes (the bar at the bottom)', keys = 'PENDING (peach)', help = 'd, c, y waiting for a motion' },
  { group = 'modes (the bar at the bottom)', keys = 'Space o ...', help = 'Waiting for more keys (hint)' },
  { group = 'modes (the bar at the bottom)', keys = 'Esc (while waiting)', help = 'Cancel, nothing happens' },
  { group = 'modes (the bar at the bottom)', keys = 'Backspace (waiting)', help = 'Take back one key' },
  { group = 'modes (the bar at the bottom)', keys = '[+]', help = 'Not saved yet' },
  { group = 'save', keys = '(nothing)', help = 'Autosave on Esc and changes' },
  { group = 'save', keys = 'Ctrl s', help = 'Save now' },
  { group = 'save', keys = ':q', help = 'Close window (:qall quits)' },
  { group = 'save', keys = ':help', help = "vis's own full key list" },
  { group = 'editing', keys = 'Alt Up / Down', help = 'Move line / selected lines' },
  { group = 'editing', keys = 'J / K (selecting)', help = 'Move selected lines down / up' },
  { group = 'editing', keys = 'x', help = 'Delete a letter (not copied)' },
  { group = 'editing', keys = 'Alt t', help = 'ISO time stamp (typing)' },
  { group = 'editing', keys = 'Alt w', help = 'Week, like W39 (typing)' },
  { group = 'editing', keys = 'Ctrl c', help = 'Leave insert mode' },
  { group = 'editing', keys = '< / >', help = 'Outdent / indent (selecting)' },
  { group = 'editing', keys = 'u / Ctrl r', help = 'Undo / redo' },
  { group = 'move & search', keys = 'Ctrl d / Ctrl u', help = 'Half page down / up' },
  { group = 'move & search', keys = 'Shift Down / Up', help = 'Half page down / up' },
  { group = 'move & search', keys = 'n / N', help = 'Next / previous match' },
  { group = 'move & search', keys = 'Ctrl j / Ctrl k', help = 'Next / previous split' },
  { group = 'move & search', keys = '/ text Enter', help = 'Search (regex)' },
  { group = 'in an org file', keys = 'cit', help = 'Change state (TODO, DONE…)' },
  { group = 'in an org file', keys = 'Tab / Shift Tab', help = 'Next / previous heading' },
  { group = 'in an org file', keys = '<< / >>', help = 'Promote / demote the heading' },
  { group = 'in an org file', keys = 'Space x', help = 'Tick a checkbox' },
  { group = 'in the agenda', keys = 'Enter', help = 'Open the task in a split' },
  { group = 'in the agenda', keys = 't', help = 'Change the state' },
  { group = 'in the agenda', keys = 'f / b', help = 'Next / previous day or week' },
  { group = 'in the agenda', keys = '.', help = 'Back to today' },
  { group = 'in the agenda', keys = 'vd / vw / vt / vc', help = 'Day / week / tasks / done' },
  { group = 'in the agenda', keys = 'r', help = 'Refresh' },
  { group = 'in the agenda', keys = 'q', help = 'Close' },
  { group = 'in a picker', keys = 'type', help = 'Narrow the list' },
  { group = 'in a picker', keys = 'Ctrl n / Ctrl p', help = 'Down / up (arrows too)' },
  { group = 'in a picker', keys = 'Enter', help = 'Open it' },
  { group = 'in a picker', keys = 'Ctrl c', help = 'Close' },
}

-- ============================================================================
--  WINDOWS, OPTIONS, STARTUP
-- ============================================================================
local wopt = util.wopt

mode.title = function(win)
  if agenda.is_agenda(win) then return 'agenda' end
  if cheat.is_panel(win) then return 'keys' end
end
mode.setup(P)

vis.events.subscribe(vis.events.INIT, function()
  vis:command('set theme catppuccin-mocha')
  pcall(function()
    vis.options.autoindent = true
    vis.options.ignorecase = true
  end)
end)

vis.events.subscribe(vis.events.WIN_OPEN, function(win)
  if agenda.is_agenda(win) then
    wopt(win, 'numbers', false)
    wopt(win, 'relativenumbers', false)
    wopt(win, 'cursorline', true)
    pcall(function() win:set_syntax('orgagenda') end)
    agenda.install(win, leader)
    return
  end
  if cheat.is_panel(win) then
    wopt(win, 'numbers', false)
    wopt(win, 'relativenumbers', false)
    cheat.install(win)
    return
  end
  wopt(win, 'numbers', true)
  wopt(win, 'relativenumbers', true)
  wopt(win, 'cursorline', true)
  wopt(win, 'expandtab', true)
  wopt(win, 'tabwidth', 4)
  wopt(win, 'breakat', ' ')
  if is_org(win) then install_org_keys(win) end
  remember(win)
end)

vis.events.subscribe(vis.events.START, function()
  local dir = util.org_dir()
  if not util.is_dir(dir) then util.mkdir_p(dir) end
  if not util.exists(org.inbox()) then util.write_lines(org.inbox(), {}) end
  local wins = {}
  for w in vis:windows() do wins[#wins + 1] = w end
  -- a plain launch opens your day
  if #wins == 1 and wins[1].file and not wins[1].file.name and wins[1].file.size == 0 then
    agenda.show('day', 0)
  end
end)
