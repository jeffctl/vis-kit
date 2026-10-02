-- kit/agenda.lua: the agenda, read straight from the .org files, no parser
-- library. A plain launch shows your day; Space o a d / a / t / c open the
-- day, the week, every open task, what you finished. It is a file in the
-- kit's cache folder with its own highlighting (lexers/orgagenda.lua) and
-- keys: Enter opens the task, t changes its state, f / b move a day or a
-- week, . is today, r refreshes, q closes.
--
-- The day reads like the Neovim kit's (its README has the rules):
--   today        what is due, starts or happens today, timed items first
--   Overdue      deadlines and appointments that passed
--   Coming up    the next 14 days: deadlines, start dates, appointments
--   Started      SCHEDULED has passed, no deadline: begun, "12d" since
--   In progress / Waiting, blocked / To do (no date) / Someday, deferred
--   Completed    closed in the last 14 days, the newest first
-- A task has one row on today. SCHEDULED is a start date, never a due date.
local util = require('kit/util')
local org = require('kit/org')

local M = {}

M.AHEAD = 14          -- days Coming up looks ahead
M.COMPLETED_DAYS = 14 -- days Completed looks back

M.path = util.cache_dir() .. '/agenda.orgagenda'
M.view = 'day'  -- day | week | tasks | done
M.offset = 0    -- days (day view) or weeks (week view) away from today
M.rows = {}     -- line number -> task

-- ---------------------------------------------------------------------------
-- reading

local function parse_file(path, tasks)
  local lines = util.read_lines(path)
  if not lines then return end
  local i = 1
  while i <= #lines do
    local level, kw, pri, title, tags = org.parse_heading(lines[i])
    if level then
      local t = { file = path, line = i, level = level, kw = kw, pri = pri, title = title, tags = tags, stamps = {} }
      local p = org.get_planning(lines, i)
      if p.SCHEDULED then t.scheduled = org.parse_stamp(p.SCHEDULED) end
      if p.DEADLINE then t.deadline = org.parse_stamp(p.DEADLINE) end
      if p.CLOSED then t.closed = org.parse_stamp(p.CLOSED) end
      local j = i + 1
      while j <= #lines and not org.level(lines[j]) do
        if not org.is_planning(lines[j]) then
          for s in lines[j]:gmatch('<(%d%d%d%d%-%d%d%-%d%d[^>]*)>') do
            local st = org.parse_stamp('<' .. s .. '>')
            if st then t.stamps[#t.stamps + 1] = st end
          end
        end
        j = j + 1
      end
      if t.kw or #t.stamps > 0 then tasks[#tasks + 1] = t end
      i = j
    else
      i = i + 1
    end
  end
end

function M.tasks()
  local tasks = {}
  for _, path in ipairs(util.org_files(util.org_dir())) do parse_file(path, tasks) end
  return tasks
end

-- ---------------------------------------------------------------------------
-- words

local function days_word(n)
  if n == 0 then return 'today' end
  if n < 0 then return (-n) .. 'd ago' end
  return 'in ' .. n .. 'd'
end

local function row(when, task, name)
  local pri = task.pri and ('· ' .. task.pri) or ''
  local title = task.title
  if name then title = title .. '   (' .. name .. ')' end
  return ('  %-11s %-11s %-4s %s'):format(when, task.kw or '', pri, title)
end

local function long_date(t)
  return os.date('%A %d %B %Y', t):gsub(' 0', ' ')
end

-- ---------------------------------------------------------------------------
-- views

local function open(t) return not (t.kw and org.done[t.kw]) end

local function appointment(t) -- the stamp that matters most: the nearest one at or after today, else the latest past
  local best
  local today = org.today()
  for _, st in ipairs(t.stamps) do
    local d = org.next_repeat(st)
    local item = { day = d, time = st.time }
    if d >= today then
      if not best or best.day < today or d < best.day then best = item end
    elseif not best or (best.day < today and d > best.day) then
      best = item
    end
  end
  return best
end

local function day_view(out, rows, base)
  local tasks = M.tasks()
  local today = org.today()
  local day_n = org.days_from_today(base)
  out[#out + 1] = long_date(base) .. (day_n == 0 and '' or ('   (' .. days_word(day_n) .. ')'))
  out[#out + 1] = string.rep('─', 60)
  local seen = {}
  local function add(list, when, task, sortkey)
    list[#list + 1] = { when = when, task = task, key = sortkey or '' }
  end
  local function section(title, list)
    if #list == 0 then return end
    table.sort(list, function(a, b) return a.key < b.key end)
    out[#out + 1] = ''
    out[#out + 1] = title:upper()
    for _, item in ipairs(list) do
      out[#out + 1] = row(item.when, item.task)
      rows[#out] = item.task
      seen[item.task] = true
    end
  end
  local todays, overdue, coming, started, inprog, waiting, todo, someday, done = {}, {}, {}, {}, {}, {}, {}, {}, {}
  for _, t in ipairs(tasks) do
    if open(t) then
      local sc = t.scheduled and org.next_repeat(t.scheduled)
      local dl = t.deadline and org.next_repeat(t.deadline)
      local ap = appointment(t)
      local placed = false
      local function at(day, time, list, label)
        if placed then return end
        local n = org.days_from_today(day) - day_n
        if n == 0 then
          add(todays, time or label or 'today', t, time or '~')
          placed = true
        elseif list == overdue and n < 0 then
          add(overdue, days_word(n), t, ('%06d'):format(100000 + n))
          placed = true
        elseif list == coming and n > 0 and n <= M.AHEAD then
          add(coming, days_word(n) .. (time and (' ' .. time) or ''), t, ('%03d'):format(n) .. (time or ''))
          placed = true
        end
      end
      -- a deadline decides first: due today, overdue, or coming up
      if dl then at(dl, t.deadline.time, overdue, 'due') end
      if dl then at(dl, t.deadline.time, coming) end
      -- a start date still ahead: coming up; today: today
      if sc and org.days_from_today(sc) - day_n >= 0 then at(sc, t.scheduled.time, coming) end
      -- an appointment: today, passed, or ahead
      if ap then at(ap.day, ap.time, overdue) end
      if ap then at(ap.day, ap.time, coming) end
      if not placed then
        if t.kw == 'INPROGRESS' then add(inprog, sc and days_word(org.days_from_today(sc)):gsub('in ', '') or '', t, t.title)
        elseif sc and org.days_from_today(sc) < 0 and not dl and t.kw ~= 'WAITING' and t.kw ~= 'BLOCKED' then
          local n = -org.days_from_today(sc)
          add(started, n .. 'd', t, ('%06d'):format(100000 - n))
        elseif t.kw == 'WAITING' or t.kw == 'BLOCKED' then add(waiting, '', t, t.title)
        elseif t.kw == 'SOMEDAY' or t.kw == 'DEFERRED' then add(someday, '', t, t.title)
        elseif t.kw and not sc and not dl and not ap then add(todo, '', t, (t.pri or 'Z') .. t.title)
        end
      end
    elseif t.closed then
      local n = org.days_from_today(t.closed.day)
      if n >= -M.COMPLETED_DAYS and n <= 0 then
        add(done, days_word(n), t, ('%06d'):format(100000 + n) .. (t.closed.time or ''))
      end
    end
  end
  table.sort(todays, function(a, b) return a.key < b.key end)
  if #todays == 0 then
    out[#out + 1] = ''
    out[#out + 1] = '  nothing due, starting or happening ' .. (day_n == 0 and 'today' or 'that day')
  else
    out[#out + 1] = ''
    for _, item in ipairs(todays) do
      out[#out + 1] = row(item.when, item.task)
      rows[#out] = item.task
    end
  end
  if day_n == 0 then
    section('Overdue', overdue)
    section('Coming up', coming)
    section('Started', started)
    section('In progress', inprog)
    section('Waiting / blocked', waiting)
    section('To do (no date)', todo)
    section('Someday / deferred', someday)
    table.sort(done, function(a, b) return a.key > b.key end)
    if #done > 0 then
      out[#out + 1] = ''
      out[#out + 1] = 'COMPLETED'
      for _, item in ipairs(done) do
        out[#out + 1] = row(item.when, item.task)
        rows[#out] = item.task
      end
    end
  end
end

local function week_view(out, rows, base)
  local tasks = M.tasks()
  local wday = os.date('*t', base).wday -- 1 = Sunday
  local monday = org.add_days(base, -((wday + 5) % 7))
  out[#out + 1] = 'Week ' .. os.date('%V', monday) .. '   ' .. os.date('%d %b', monday):gsub('^0', '') .. ' to ' ..
    os.date('%d %b %Y', org.add_days(monday, 6)):gsub('^0', '')
  out[#out + 1] = string.rep('─', 60)
  for d = 0, 6 do
    local day = org.add_days(monday, d)
    local n = org.days_from_today(day)
    out[#out + 1] = ''
    out[#out + 1] = (long_date(day) .. (n == 0 and '   (today)' or '')):upper()
    local items = {}
    for _, t in ipairs(tasks) do
      if open(t) then
        local function same(st, label)
          if st and org.days_from_today(org.next_repeat(st)) == n then
            items[#items + 1] = { when = st.time or label, task = t, key = st.time or '~' }
          end
        end
        same(t.deadline, 'due')
        if not t.deadline or org.days_from_today(org.next_repeat(t.deadline)) ~= n then same(t.scheduled, 'start') end
        for _, st in ipairs(t.stamps) do same(st, '') end
      end
    end
    table.sort(items, function(a, b) return a.key < b.key end)
    for _, item in ipairs(items) do
      out[#out + 1] = row(item.when, item.task)
      rows[#out] = item.task
    end
  end
end

local function tasks_view(out, rows)
  out[#out + 1] = 'Every open task, file by file'
  out[#out + 1] = string.rep('─', 60)
  local dir = util.org_dir()
  local last
  for _, t in ipairs(M.tasks()) do
    if t.kw and open(t) then
      if t.file ~= last then
        out[#out + 1] = ''
        out[#out + 1] = util.relative(t.file, dir):upper()
        last = t.file
      end
      local when = ''
      if t.deadline then when = days_word(org.days_from_today(org.next_repeat(t.deadline)))
      elseif t.scheduled then when = 'start ' .. days_word(org.days_from_today(org.next_repeat(t.scheduled))):gsub('^in ', '+') end
      out[#out + 1] = row(when, t)
      rows[#out] = t
    end
  end
end

local function done_view(out, rows)
  out[#out + 1] = 'Done, newest first'
  out[#out + 1] = string.rep('─', 60)
  local list = {}
  for _, t in ipairs(M.tasks()) do
    if t.kw and org.done[t.kw] then
      list[#list + 1] = t
    end
  end
  table.sort(list, function(a, b)
    local da, db = a.closed and a.closed.day or 0, b.closed and b.closed.day or 0
    if da ~= db then return da > db end
    return (a.closed and a.closed.time or '') > (b.closed and b.closed.time or '')
  end)
  local last
  for _, t in ipairs(list) do
    local key = t.closed and os.date('%Y-%m-%d', t.closed.day) or 'no close date'
    if key ~= last then
      out[#out + 1] = ''
      out[#out + 1] = (t.closed and (long_date(t.closed.day) .. '   (' .. days_word(org.days_from_today(t.closed.day)) .. ')') or 'NO CLOSE DATE'):upper()
      last = key
    end
    out[#out + 1] = row(t.closed and t.closed.time or '', t)
    rows[#out] = t
  end
end

-- the current view as lines; fills M.rows
function M.render()
  local out, rows = {}, {}
  local names = { day = 'MY DAY', week = 'THE WEEK', tasks = 'OPEN TASKS', done = 'DONE' }
  out[#out + 1] = names[M.view]
  out[#out + 1] = 'vd day  vw week  vt tasks  vc done · Enter open  t state  f/b next/back  . today  r reload  q close'
  out[#out + 1] = ''
  if M.view == 'day' then day_view(out, rows, org.add_days(org.today(), M.offset))
  elseif M.view == 'week' then week_view(out, rows, org.add_days(org.today(), 7 * M.offset))
  elseif M.view == 'tasks' then tasks_view(out, rows)
  else done_view(out, rows) end
  M.rows = rows
  return out
end

-- ---------------------------------------------------------------------------
-- the window

function M.is_agenda(win)
  local path = win and win.file and win.file.path
  return path ~= nil and (path == M.path or path:match('/vis%-kit/agenda%.orgagenda$') ~= nil)
end

function M.window()
  for win in vis:windows() do
    if M.is_agenda(win) then return win end
  end
end

-- write the view and show it: in its window when open, else in a new one
-- (or in the current window when that is empty and unnamed)
function M.show(view, offset)
  if view then M.view = view end
  if offset ~= nil then M.offset = offset end
  for w in vis:windows() do util.save(w) end
  util.write_lines(M.path, M.render())
  local win = M.window()
  if win then
    local line = vis.win == win and win.selection.line or 1
    vis.win = win
    vis:command('e!')
    local n = #vis.win.file.lines
    vis.win.selection:to(math.max(1, math.min(line, n)), 1)
  else
    local cur = vis.win
    if cur and cur.file and not cur.file.name and cur.file.size == 0 then
      vis:command('e ' .. util.cmd_escape(M.path))
    else
      vis:command('open ' .. util.cmd_escape(M.path))
    end
    local first
    for n in pairs(M.rows) do
      if not first or n < first then first = n end
    end
    if first and M.is_agenda(vis.win) then vis.win.selection:to(first, 1) end
  end
end

function M.refresh()
  M.show()
end

local function task_here()
  local t = M.rows[vis.win.selection.line]
  if not t then vis:info('Not on a task') end
  return t
end

-- open the task's file in a split, on its line
local function open_task()
  local t = task_here()
  if not t then return end
  local win = util.window_of(t.file)
  if win then
    vis.win = win
  elseif not vis:command('split ' .. util.cmd_escape(t.file)) then
    return
  end
  vis.win.selection:to(t.line, 1)
end

function M.set_state(t, kw)
  local old
  org.edit_path(t.file, function(lines)
    if not org.level(lines[t.line]) then return false end
    old = org.set_state(lines, t.line, kw)
  end)
  return old
end

-- the keys of the agenda window; `leader` is kit/leader for the state menu
function M.install(win, leader)
  local N = vis.modes.NORMAL
  win:map(N, '<Enter>', open_task, 'Open the task in a split')
  win:map(N, 'r', function() M.refresh() end, 'Refresh the agenda')
  win:map(N, 'q', function()
    local n = 0
    for _ in vis:windows() do n = n + 1 end
    if n <= 1 then vis:command('qall') else win:close(true) end
  end, 'Close the agenda')
  win:map(N, '.', function() M.show(nil, 0) end, 'Back to today')
  win:map(N, 'f', function()
    if M.view == 'day' or M.view == 'week' then M.show(nil, M.offset + 1) end
  end, 'Next day / week')
  win:map(N, 'b', function()
    if M.view == 'day' or M.view == 'week' then M.show(nil, M.offset - 1) end
  end, 'Previous day / week')
  leader.map_window(win, N, 'v', { name = 'view', keys = {
    d = { help = 'Day view', run = function() M.show('day', 0) end },
    w = { help = 'Week view', run = function() M.show('week', 0) end },
    t = { help = 'Every open task', run = function() M.show('tasks') end },
    c = { help = 'Done, newest first', run = function() M.show('done') end },
  } }, 'Switch the agenda view')
  leader.map_window(win, N, 't', leader.pick('State', org.state_options, function(kw)
    local t = task_here()
    if not t then return end
    local line = vis.win.selection.line
    M.set_state(t, kw)
    M.show()
    vis.win.selection:to(math.min(line, #vis.win.file.lines), 1)
  end), 'Change the state of the task')
end

return M
