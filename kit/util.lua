-- kit/util.lua: small helpers the other kit modules share. Nothing here maps
-- a key. Plain Lua 5.2+ and POSIX tools only (find, mkdir, test): a Mac,
-- Alpine in iSH, Termux and any Linux all have them.
local M = {}

M.home = os.getenv('HOME') or ''

-- quote for /bin/sh
function M.shq(s)
  return "'" .. (tostring(s):gsub("'", "'\\''")) .. "'"
end

-- escape a path for a vis : command (its parser splits on blanks, \ escapes)
function M.cmd_escape(path)
  return (path:gsub('([%s\\])', '\\%1'))
end

function M.is_dir(path)
  return os.execute('test -d ' .. M.shq(path)) == true
end

function M.exists(path)
  local f = io.open(path, 'rb')
  if f then f:close() return true end
  return false
end

function M.mkdir_p(path)
  os.execute('mkdir -p ' .. M.shq(path))
end

function M.basename(path)
  return (path:gsub('/+$', ''):match('([^/]*)$'))
end

function M.dirname(path)
  local dir = path:match('^(.*)/[^/]*$')
  if dir == nil then return '.' end
  if dir == '' then return '/' end
  return dir
end

-- a path relative to the org folder, for the agenda's file names
function M.relative(path, dir)
  if dir and path:sub(1, #dir + 1) == dir .. '/' then return path:sub(#dir + 2) end
  return path
end

-- the cache folder for the files the kit writes for itself (agenda, keys panel, recent files)
function M.cache_dir()
  local dir = os.getenv('XDG_CACHE_HOME')
  if not dir or dir == '' then dir = M.home .. '/.cache' end
  dir = dir .. '/vis-kit'
  M.mkdir_p(dir)
  return dir
end

-- Your org files: $ORG_DIR when set; on a Mac beorg's iCloud folder when it
-- is there (phone and Mac share one set of files); else ~/org.
local org_dir
function M.org_dir()
  if org_dir then return org_dir end
  local env = os.getenv('ORG_DIR')
  if env and env ~= '' then
    org_dir = env
  else
    local beorg = M.home .. '/Library/Mobile Documents/iCloud~com~appsonthemove~beorg/Documents/org'
    org_dir = M.is_dir(beorg) and beorg or (M.home .. '/org')
  end
  return org_dir
end

-- run vis-menu over `lines`, fullscreen, and return the chosen line or nil.
-- Writes the choices to a temp file and redirects it in, because vis 0.9's
-- vis:pipe cannot take a Lua string as stdin (only master can); the
-- (nil, nil, cmd, fullscreen) form runs the shell command on both.
function M.menu(lines, prompt)
  if #lines == 0 then return nil end
  local tmp = M.cache_dir() .. '/menu.txt'
  local f = io.open(tmp, 'wb')
  if not f then return nil end
  f:write(table.concat(lines, '\n'), '\n')
  f:close()
  local cmd = 'vis-menu -i -b -l 15 -p ' .. M.shq(prompt) .. ' < ' .. M.shq(tmp)
  local code, out = vis:pipe(nil, nil, cmd, true)
  os.remove(tmp)
  if code ~= 0 or not out or not out:match('%S') then return nil end
  return (out:gsub('%s+$', ''))
end

function M.have(tool)
  local out = M.sh('command -v ' .. M.shq(tool))
  return out ~= nil and out ~= ''
end

function M.read_lines(path)
  local f = io.open(path, 'rb')
  if not f then return nil end
  local lines = {}
  for line in f:lines() do lines[#lines + 1] = (line:gsub('\r$', '')) end
  f:close()
  return lines
end

function M.write_lines(path, lines)
  local f, err = io.open(path, 'wb')
  if not f then return nil, err end
  f:write(table.concat(lines, '\n'), #lines > 0 and '\n' or '')
  f:close()
  return true
end

-- every .org file under dir, sorted
function M.org_files(dir)
  local out = {}
  local p = io.popen('find ' .. M.shq(dir) .. ' -name "*.org" -type f 2>/dev/null | sort')
  if p then
    for line in p:lines() do out[#out + 1] = line end
    p:close()
  end
  return out
end

-- the output of a shell command, trailing newline removed
function M.sh(cmd)
  local p = io.popen(cmd .. ' 2>/dev/null')
  if not p then return nil end
  local out = p:read('a') or ''
  p:close()
  return (out:gsub('\n$', ''))
end

-- ---------------------------------------------------------------------------
-- windows and files

-- the window showing `path`, if one does
function M.window_of(path)
  for win in vis:windows() do
    if win.file and win.file.path == path then return win end
  end
end

-- the lines of an open file as a table (no trailing newlines)
function M.file_lines(file)
  local lines = {}
  for line in file:lines_iterator() do lines[#lines + 1] = line end
  if #lines > 0 and lines[#lines] == '' and file.size > 0 and file:content(file.size - 1, 1) == '\n' then
    lines[#lines] = nil
  end
  return lines
end

-- the 0-based byte offset where line n (1-based) starts
function M.line_offset(file, n)
  if n <= 1 then return 0 end
  local data = file:content(0, file.size)
  local pos, line = 0, 1
  while line < n do
    local nl = data:find('\n', pos + 1, true)
    if not nl then return file.size end
    pos, line = nl, line + 1
  end
  return pos
end

-- the 1-based line holding the 0-based byte offset pos
function M.line_of(file, pos)
  if pos <= 0 then return 1 end
  local data = file:content(0, math.min(pos, file.size))
  local _, n = data:gsub('\n', '')
  return n + 1
end

-- replace lines first..last (1-based, inclusive) with the list `new`.
-- last = first - 1 inserts before line first.
function M.splice(file, first, last, new)
  local start = M.line_offset(file, first)
  local finish = last >= first and M.line_offset(file, last + 1) or start
  if finish > start then file:delete(start, finish - start) end
  if #new > 0 then
    local text = table.concat(new, '\n') .. '\n'
    if start == file.size and start > 0 and file:content(start - 1, 1) ~= '\n' then
      text = '\n' .. text
    end
    file:insert(start, text)
  end
end

-- set a per-window option, falling back to :set on builds without win.options
function M.wopt(win, name, value)
  local ok = pcall(function() win.options[name] = value end)
  if not ok then vis:command('set ' .. name .. ' ' .. tostring(value)) end
end

-- write a window's file when it has a name and changes
function M.save(win)
  local file = win and win.file
  if not file or not file.path or not file.modified then return true end
  -- never write while a visual selection is active: vis's :w would write only
  -- the selection and shrink the file
  if vis.mode == vis.modes.VISUAL or vis.mode == vis.modes.VISUAL_LINE then return true end
  local prev = vis.win
  if prev ~= win then vis.win = win end
  local ok = vis:command('w')
  if prev and prev ~= win then vis.win = prev end
  return ok
end

return M
