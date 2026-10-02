-- kit/org.lua: the org keys without orgmode. Plain-text functions on a table
-- of lines (used on open files and, from the agenda, on files on disk):
-- TODO state with CLOSED and :START:, SCHEDULED / DEADLINE, priority,
-- checkboxes, promote / demote, captures into inbox.org, time stamps.
-- The file format is org's, the same files beorg, Emacs and the Neovim kit
-- read; nothing here is specific to vis.
local util = require('kit/util')

local M = {}

M.keywords = { 'TODO', 'INPROGRESS', 'WAITING', 'BLOCKED', 'SCHEDULED', 'DEFERRED', 'SOMEDAY',
               'DONE', 'DELEGATED', 'CANCELLED' }
M.is_keyword = {}
for _, k in ipairs(M.keywords) do M.is_keyword[k] = true end
M.done = { DONE = true, DELEGATED = true, CANCELLED = true }

-- the cit menu: the letter, the state, the value written (nil = the state)
M.state_options = {
  { 't', 'TODO' }, { 'i', 'INPROGRESS' }, { 'w', 'WAITING' }, { 'b', 'BLOCKED' },
  { 's', 'SCHEDULED' }, { 'f', 'DEFERRED' }, { 'o', 'SOMEDAY' },
  { 'd', 'DONE' }, { 'g', 'DELEGATED' }, { 'c', 'CANCELLED' }, { '<Space>', 'none', '' },
}
M.priority_options = {
  { 'a', 'A' }, { 'b', 'B' }, { 'c', 'C' }, { 'd', 'D' }, { 'e', 'E' }, { 'f', 'F' }, { '<Space>', 'none', '' },
}

-- ---------------------------------------------------------------------------
-- dates

local DAYS = { 'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat' }
local WEEKDAY = { sun = 1, mon = 2, tue = 3, wed = 4, thu = 5, fri = 6, sat = 7 }

-- noon of the day holding t (noon, so adding days never trips over DST)
function M.day(t)
  local d = os.date('*t', t or os.time())
  return os.time({ year = d.year, month = d.month, day = d.day, hour = 12 })
end

function M.today() return M.day() end

function M.add_days(t, n) return M.day(t + n * 86400) end

function M.add_months(t, n)
  local d = os.date('*t', t)
  return os.time({ year = d.year, month = d.month + n, day = d.day, hour = 12 })
end

-- whole days from today to t (negative = past)
function M.days_from_today(t)
  return math.floor((M.day(t) - M.today()) / 86400 + 0.5)
end

-- an org time stamp: <2026-10-02 Thu>, [2026-10-02 Thu 12:30]
function M.stamp(t, active, time)
  t = t or os.time()
  local d = os.date('*t', t)
  local s = ('%04d-%02d-%02d %s'):format(d.year, d.month, d.day, DAYS[d.wday])
  if time == true then s = s .. os.date(' %H:%M', t)
  elseif type(time) == 'string' and time ~= '' then s = s .. ' ' .. time end
  if active then return '<' .. s .. '>' end
  return '[' .. s .. ']'
end

-- an org stamp back into parts: day (noon time), time 'HH:MM' or nil, repeat {n, unit} or nil
function M.parse_stamp(s)
  local y, m, d = s:match('[<%[](%d%d%d%d)%-(%d%d)%-(%d%d)')
  if not y then return nil end
  local t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  local time = s:match('%s(%d%d?:%d%d)')
  local rn, ru = s:match('[%+%.]+(%d+)([dwmy])')
  local out = { day = t, time = time, text = s }
  if rn then out.rep = { n = tonumber(rn), unit = ru } end
  return out
end

-- the next day of a repeating stamp on or after today
function M.next_repeat(st)
  local t = st.day
  if not st.rep then return t end
  local today = M.today()
  for _ = 1, 400 do
    if t >= today then return t end
    if st.rep.unit == 'd' then t = M.add_days(t, st.rep.n)
    elseif st.rep.unit == 'w' then t = M.add_days(t, 7 * st.rep.n)
    elseif st.rep.unit == 'm' then t = M.add_months(t, st.rep.n)
    else t = M.add_months(t, 12 * st.rep.n) end
  end
  return t
end

-- What you type at a date prompt: empty = today, "+3" / "+3d" / "2w" days or
-- weeks ahead, "fri" the next Friday, "tomorrow", "2026-10-05", "10-05",
-- "1m" a month on. A time may follow: "fri 10:00". Returns noon of the day
-- and the time, or nil and why not.
function M.parse_date(text)
  text = (text or ''):lower():gsub('^%s+', ''):gsub('%s+$', '')
  local time = text:match('(%d%d?:%d%d)$')
  if time then
    text = text:sub(1, #text - #time):gsub('%s+$', '')
    local h, mi = time:match('(%d+):(%d+)')
    time = ('%02d:%02d'):format(tonumber(h), tonumber(mi))
  end
  local t = M.today()
  if text == '' or text == 'today' or text == '.' then
    -- today
  elseif text == 'tomorrow' or text == 'tom' then t = M.add_days(t, 1)
  elseif text:match('^%+?%d+$') then t = M.add_days(t, tonumber(text:match('%d+')))
  elseif text:match('^%+?%d+[dwmy]$') then
    local n, u = text:match('(%d+)([dwmy])')
    n = tonumber(n)
    if u == 'd' then t = M.add_days(t, n)
    elseif u == 'w' then t = M.add_days(t, 7 * n)
    elseif u == 'm' then t = M.add_months(t, n)
    else t = M.add_months(t, 12 * n) end
  elseif text:match('^%d%d%d%d%-%d%d?%-%d%d?$') then
    local y, m, d = text:match('(%d+)%-(%d+)%-(%d+)')
    t = os.time({ year = tonumber(y), month = tonumber(m), day = tonumber(d), hour = 12 })
  elseif text:match('^%d%d?%-%d%d?$') then
    local m, d = text:match('(%d+)%-(%d+)')
    local now = os.date('*t')
    t = os.time({ year = now.year, month = tonumber(m), day = tonumber(d), hour = 12 })
    if t < M.today() then t = os.time({ year = now.year + 1, month = tonumber(m), day = tonumber(d), hour = 12 }) end
  elseif WEEKDAY[text:sub(1, 3)] and text:match('^%a+$') then
    local want = WEEKDAY[text:sub(1, 3)]
    local wday = os.date('*t', t).wday
    local ahead = (want - wday) % 7
    if ahead == 0 then ahead = 7 end
    t = M.add_days(t, ahead)
  else
    return nil, 'Not a date: ' .. text .. '  (try 2026-10-05, +3, fri, tomorrow)'
  end
  return t, time
end

-- ---------------------------------------------------------------------------
-- headings

function M.level(line)
  local stars = line and line:match('^(%*+)%s')
  return stars and #stars or nil
end

-- level, keyword, priority, title, tags of a heading line (nil when it is none)
function M.parse_heading(line)
  local stars, rest = line:match('^(%*+)%s+(.*)$')
  if not stars then
    stars = line:match('^(%*+)$')
    if not stars then return nil end
    rest = ''
  end
  local kw
  local word = rest:match('^(%u+)%f[%s]') or rest:match('^(%u+)$')
  if word and M.is_keyword[word] then
    kw = word
    rest = rest:sub(#word + 1):gsub('^%s+', '')
  end
  local pri = rest:match('^%[#(%u)%]')
  if pri then rest = rest:sub(5):gsub('^%s+', '') end
  local tags = rest:match('%s+(:[%w_@#%%:]+:)%s*$') or ((rest:match('^(:[%w_@#%%:]+:)%s*$')))
  if tags then rest = rest:gsub('%s*:[%w_@#%%:]+:%s*$', '') end
  return #stars, kw, pri, rest, tags
end

function M.make_heading(level, kw, pri, title, tags)
  local parts = { string.rep('*', level) }
  if kw and kw ~= '' then parts[#parts + 1] = kw end
  if pri and pri ~= '' then parts[#parts + 1] = '[#' .. pri .. ']' end
  if title and title ~= '' then parts[#parts + 1] = title end
  local s = table.concat(parts, ' ')
  if tags and tags ~= '' then s = s .. ' ' .. tags end
  return s
end

-- the heading at line n or above it; nil when there is none
function M.heading_above(lines, n)
  for i = math.min(n, #lines), 1, -1 do
    if M.level(lines[i]) then return i end
  end
end

function M.next_heading(lines, n)
  for i = n + 1, #lines do if M.level(lines[i]) then return i end end
end

function M.prev_heading(lines, n)
  for i = n - 1, 1, -1 do if M.level(lines[i]) then return i end end
end

-- the last line of the heading's subtree
function M.subtree_end(lines, h)
  local level = M.level(lines[h])
  for i = h + 1, #lines do
    local l = M.level(lines[i])
    if l and l <= level then return i - 1 end
  end
  return #lines
end

local function is_planning(line)
  return line ~= nil and (line:match('^%s*CLOSED:') or line:match('^%s*SCHEDULED:') or line:match('^%s*DEADLINE:')) ~= nil
end
M.is_planning = is_planning

-- { SCHEDULED = '<...>', DEADLINE = '<...>', CLOSED = '[...]' } and the line it sits on
function M.get_planning(lines, h)
  local line = lines[h + 1]
  if not is_planning(line) then return {}, nil end
  local p = {}
  for key, val in line:gmatch('(%u+):%s*([<%[][^>%]]*[>%]])') do p[key] = val end
  return p, h + 1
end

local function indent_for(lines, h)
  return string.rep(' ', (M.level(lines[h]) or 1) + 1)
end

-- set (value) or drop (nil) one of CLOSED / SCHEDULED / DEADLINE
function M.set_planning(lines, h, key, value)
  local p, idx = M.get_planning(lines, h)
  p[key] = value
  local parts = {}
  for _, k in ipairs({ 'CLOSED', 'SCHEDULED', 'DEADLINE' }) do
    if p[k] then parts[#parts + 1] = k .. ': ' .. p[k] end
  end
  if #parts == 0 then
    if idx then table.remove(lines, idx) end
  elseif idx then
    lines[idx] = indent_for(lines, h) .. table.concat(parts, ' ')
  else
    table.insert(lines, h + 1, indent_for(lines, h) .. table.concat(parts, ' '))
  end
end

-- the :PROPERTIES: drawer right under the heading (after its planning line): first and last line
function M.drawer(lines, h)
  local _, pidx = M.get_planning(lines, h)
  local i = (pidx or h) + 1
  if lines[i] and lines[i]:match('^%s*:PROPERTIES:%s*$') then
    for j = i + 1, #lines do
      if lines[j]:match('^%s*:END:%s*$') then return i, j end
      if M.level(lines[j]) then break end
    end
  end
end

function M.get_property(lines, h, name)
  local first, last = M.drawer(lines, h)
  if not first then return nil end
  for j = first + 1, last - 1 do
    local v = lines[j]:match('^%s*:' .. name .. ':%s*(.-)%s*$')
    if v then return v end
  end
end

function M.set_property(lines, h, name, value)
  local indent = indent_for(lines, h)
  local first, last = M.drawer(lines, h)
  if first then
    for j = first + 1, last - 1 do
      if lines[j]:match('^%s*:' .. name .. ':') then
        lines[j] = indent .. ':' .. name .. ': ' .. value
        return
      end
    end
    table.insert(lines, last, indent .. ':' .. name .. ': ' .. value)
  else
    local _, pidx = M.get_planning(lines, h)
    local at = (pidx or h) + 1
    table.insert(lines, at, indent .. ':PROPERTIES:')
    table.insert(lines, at + 1, indent .. ':' .. name .. ': ' .. value)
    table.insert(lines, at + 2, indent .. ':END:')
  end
end

-- change the state of heading h. A done state writes CLOSED, leaving one
-- removes it; INPROGRESS gets :START: now when it has none (as the Neovim kit does)
function M.set_state(lines, h, kw)
  local level, old, pri, title, tags = M.parse_heading(lines[h])
  if not level then return nil end
  lines[h] = M.make_heading(level, kw, pri, title, tags)
  if M.done[kw] then
    M.set_planning(lines, h, 'CLOSED', M.stamp(os.time(), false, true))
  elseif old and M.done[old] then
    M.set_planning(lines, h, 'CLOSED', nil)
  end
  if kw == 'INPROGRESS' and old ~= 'INPROGRESS' then
    local start = M.get_property(lines, h, 'START')
    if not start or start == '' then M.set_property(lines, h, 'START', M.stamp(os.time(), false, true)) end
  end
  return old
end

function M.set_priority(lines, h, pri)
  local level, kw, _, title, tags = M.parse_heading(lines[h])
  if not level then return false end
  lines[h] = M.make_heading(level, kw, pri ~= '' and pri or nil, title, tags)
  return true
end

function M.set_tags(lines, h, tags)
  local level, kw, pri, title = M.parse_heading(lines[h])
  if not level then return false end
  tags = tags:gsub('^%s+', ''):gsub('%s+$', ''):gsub('[%s,]+', ':')
  if tags ~= '' then tags = ':' .. tags:gsub('^:+', ''):gsub(':+$', '') .. ':' end
  lines[h] = M.make_heading(level, kw, pri, title, tags ~= '' and tags or nil)
  return true
end

-- "- [ ] text" <-> "- [X] text"; "- text" gets a box. nil when the line is no list item
function M.tick(line)
  local pre, box, rest = line:match('^(%s*[-+]%s+)%[([ xX%-])%](.*)$')
  if not pre then pre, box, rest = line:match('^(%s+%*%s+)%[([ xX%-])%](.*)$') end
  if not pre then pre, box, rest = line:match('^(%s*%d+[.)]%s+)%[([ xX%-])%](.*)$') end
  if pre then return pre .. '[' .. (box == ' ' and 'X' or ' ') .. ']' .. rest end
  local bullet = line:match('^%s*[-+]%s+') or line:match('^%s+%*%s+') or line:match('^%s*%d+[.)]%s+')
  if bullet then return bullet .. '[ ] ' .. line:sub(#bullet + 1) end
  return nil
end

-- the heading and everything under it one level deeper (n = 1) or back (n = -1)
function M.shift(lines, h, n)
  local last = M.subtree_end(lines, h)
  for i = h, last do
    local level = M.level(lines[i])
    if level then
      if level + n < 1 then return false end
      lines[i] = string.rep('*', level + n) .. lines[i]:sub(level + 1)
    end
  end
  return true
end

-- ---------------------------------------------------------------------------
-- applying changes

-- Run fn(lines, cursor_line) on a copy of the window's lines and write only
-- the lines that changed back. fn returning false means: nothing to do.
function M.apply(win, fn)
  local file = win.file
  local old = util.file_lines(file)
  local new = {}
  for i, l in ipairs(old) do new[i] = l end
  if fn(new, win.selection.line) == false then return false end
  local first = 1
  while first <= #old and first <= #new and old[first] == new[first] do first = first + 1 end
  local oend, nend = #old, #new
  while oend >= first and nend >= first and old[oend] == new[nend] do
    oend, nend = oend - 1, nend - 1
  end
  if first > #old and first > #new then return true end
  local repl = {}
  for i = first, nend do repl[#repl + 1] = new[i] end
  util.splice(file, first, oend, repl)
  return true
end

-- The same on a file by path: through its window when it is open (and
-- saved right away), else on disk. A missing file starts empty.
function M.edit_path(path, fn)
  local win = util.window_of(path)
  if win then
    local ok = M.apply(win, fn)
    if ok then util.save(win) end
    return ok
  end
  local lines = util.read_lines(path) or {}
  if fn(lines, 1) == false then return false end
  util.mkdir_p(util.dirname(path))
  return util.write_lines(path, lines)
end

-- ---------------------------------------------------------------------------
-- captures

function M.inbox()
  return util.org_dir() .. '/inbox.org'
end

-- kind: 't' task, 's' task with a start date, 'd' task with a due date, 'n' note
function M.capture(kind, title, date)
  local block = { (kind == 'n' and '* ' or '* TODO ') .. title }
  if kind == 's' and date then block[#block + 1] = '  SCHEDULED: ' .. date end
  if kind == 'd' and date then block[#block + 1] = '  DEADLINE: ' .. date end
  block[#block + 1] = '  ' .. M.stamp(os.time(), false)
  local ok, err = M.edit_path(M.inbox(), function(lines)
    for _, l in ipairs(block) do lines[#lines + 1] = l end
  end)
  return ok, err
end

-- ---------------------------------------------------------------------------
-- stamps while typing (the VS Code habit)

-- 2026-09-25T21:52:08-07:00
function M.iso_now()
  local t = os.time()
  local utc = os.date('!*t', t)
  utc.isdst = os.date('*t', t).isdst
  local off = os.difftime(t, os.time(utc))
  local sign = off < 0 and '-' or '+'
  off = math.abs(off)
  return os.date('%Y-%m-%dT%H:%M:%S', t)
    .. ('%s%02d:%02d'):format(sign, math.floor(off / 3600), math.floor(off % 3600 / 60))
end

function M.iso_week()
  return 'W' .. os.date('%V')
end

return M
