-- kit/leader.lua: Space as a leader key that never times out, with hints,
-- and one-line prompts. Built on vis's key handler contract: a mapped Lua
-- function gets the keys typed after the mapping and returns how many bytes
-- it used, or -1 for "not enough yet, call me again with more". vis then
-- waits as long as you like; the pending keys show in the mode bar.
--
-- A tree of keys is a plain table:
--   group:  { name = 'org', keys = { a = node, c = node, ... } }
--   action: { help = 'Your day', run = function() ... end }
--   prompt: { help = 'Set a deadline', prompt = 'Due date: ', default = 'string or function',
--             apply = function(text) ... end }
--   pick:   { help = 'Change state', title = 'State', pick = { { 't', 'TODO' }, ... },
--             apply = function(value) ... end }
-- apply() may return another prompt or pick to continue (a capture asks for
-- a title, then a date). Since vis re-runs the handler from the first key
-- each time more input arrives, a step that returns the next step must have
-- no side effects: only the last apply() changes anything.
local M = {}

local NAMES = {
  ['<Space>'] = 'Space', ['<Enter>'] = 'Enter', ['<Escape>'] = 'Esc', ['<Backspace>'] = 'Backspace',
  ['<Tab>'] = 'Tab', ['<S-Tab>'] = 'Shift Tab', ['<Up>'] = 'Up', ['<Down>'] = 'Down',
  ['<Left>'] = 'Left', ['<Right>'] = 'Right', ['<Delete>'] = 'Delete',
}

-- "<C-s>" -> "Ctrl s", "<M-Up>" -> "Alt Up"
function M.keyname(key)
  if NAMES[key] then return NAMES[key] end
  local mods, base = key:match('^<([CSM%-]-)%-?([^<>]+)>$')
  if mods and (key:find('^<[CSM]%-')) then
    local out = NAMES['<' .. base .. '>'] or base
    if mods:find('S') then out = 'Shift ' .. out end
    if mods:find('M') then out = 'Alt ' .. out end
    if mods:find('C') then out = 'Ctrl ' .. out end
    return out
  end
  return key
end

local function utf8_len(byte)
  if byte < 0x80 then return 1 elseif byte < 0xE0 then return 2 elseif byte < 0xF0 then return 3 end
  return 4
end

-- the keys as vis writes them into its queue, each with the number of bytes it
-- takes in `keys` (a raw space is 1 byte but we name it <Space>, so the two
-- must be tracked apart: the key handler must return real bytes consumed).
function M.tokens(keys)
  local out, i, n = {}, 1, #keys
  while i <= n do
    local sym = keys:match('^<[%w%-]+>', i)
    if sym then
      out[#out + 1] = { tok = sym, bytes = #sym }
      i = i + #sym
    elseif keys:sub(i, i) == ' ' then
      out[#out + 1] = { tok = '<Space>', bytes = 1 }
      i = i + 1
    else
      local len = utf8_len(keys:byte(i))
      out[#out + 1] = { tok = keys:sub(i, i + len - 1), bytes = len }
      i = i + len
    end
  end
  return out
end

-- pending keys as words, for the mode bar: "<Space>oa" -> "Space o a"
function M.pretty(keys)
  local words = {}
  for _, k in ipairs(M.tokens(keys)) do words[#words + 1] = M.keyname(k.tok) end
  return table.concat(words, ' ')
end

local function chop(s) -- drop the last character (UTF-8 aware)
  local n = #s
  while n > 1 and s:byte(n) >= 0x80 and s:byte(n) < 0xC0 do n = n - 1 end
  return s:sub(1, n - 1)
end

local function sorted_keys(node)
  local keys = {}
  for k in pairs(node.keys) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b)
    local ga, gb = node.keys[a].keys ~= nil, node.keys[b].keys ~= nil
    if ga ~= gb then return not ga end -- actions first, groups after
    return a < b
  end)
  return keys
end

-- the keys to show in a hint: groups first (the way further in), then the
-- direct actions; hidden ones left out
local function shown_keys(node)
  local groups, actions = {}, {}
  for _, k in ipairs(sorted_keys(node)) do
    if not node.keys[k].hidden then
      if node.keys[k].keys then groups[#groups + 1] = k else actions[#actions + 1] = k end
    end
  end
  for _, k in ipairs(actions) do groups[#groups + 1] = k end
  return groups
end

local function short(text, n)
  if #text <= n then return text end
  return text:sub(1, n - 1) .. '…'
end

local function group_hint(trail, node)
  local parts = {}
  for _, k in ipairs(shown_keys(node)) do
    local child = node.keys[k]
    local label = child.keys and ('+' .. (child.name or '')) or short(child.hint or child.help or '', 18)
    parts[#parts + 1] = M.keyname(k) .. ' ' .. label
  end
  return trail .. ' ›  ' .. table.concat(parts, '  ')
end

local function pick_hint(node)
  local parts = {}
  for _, opt in ipairs(node.pick) do parts[#parts + 1] = M.keyname(opt[1]) .. ' ' .. opt[2] end
  return (node.title or 'Pick') .. ':  ' .. table.concat(parts, '  ')
end

local function find_pick(options, key)
  for _, opt in ipairs(options) do
    if opt[1] == key then return opt end
  end
end

local function resolve(root, path)
  local node = root
  for _, k in ipairs(path) do node = node.keys[k] end
  return node
end

-- the active prompt's text, so the mode bar can leave the raw keys out
M.prompting = false

local function show(msg)
  vis:info(msg)
end

-- run the key tree `root` against the typed keys; returns bytes used or -1
function M.drive(root, label, keys)
  local toks = M.tokens(keys)
  local used, i = 0, 1
  local node, path, buf = root, {}, nil
  M.prompting = false
  local function take()
    local t = toks[i]
    i, used = i + 1, used + t.bytes
    return t.tok
  end
  local function trail()
    local words = { label }
    for _, k in ipairs(path) do words[#words + 1] = M.keyname(k) end
    return table.concat(words, ' ')
  end
  while true do
    if node.prompt then
      local label_text = node.prompt
      if type(label_text) == 'function' then label_text = label_text() end
      if buf == nil then
        local d = node.default
        if type(d) == 'function' then d = d() end
        buf = d or ''
      end
      if i > #toks then
        M.prompting = true
        show(label_text .. buf .. '▏')
        return -1
      end
      local k = take()
      if k == '<Escape>' then show('') return used end
      if k == '<Enter>' then
        local nxt = node.apply(buf)
        if type(nxt) == 'table' then node, buf = nxt, nil else return used end
      elseif k == '<Backspace>' then buf = chop(buf)
      elseif k == '<C-u>' then buf = ''
      elseif k == '<Space>' then buf = buf .. ' '
      elseif k == '<Tab>' then buf = buf .. '\t'
      elseif k:sub(1, 1) == '<' and #k > 1 then -- other special keys: ignored
      else buf = buf .. k end
    elseif node.pick then
      if i > #toks then show(pick_hint(node)) return -1 end
      local k = take()
      if k == '<Escape>' then show('') return used end
      local opt = find_pick(node.pick, k)
      if not opt then
        show((node.title or 'Pick') .. ': ' .. M.keyname(k) .. ' is not one of the choices')
        return used
      end
      local value = opt[3]
      if value == nil then value = opt[2] end
      local nxt = node.apply(value)
      if type(nxt) == 'table' then node, buf = nxt, nil else return used end
    elseif node.keys then
      if i > #toks then show(group_hint(trail(), node)) return -1 end
      local k = take()
      if k == '<Escape>' then show('') return used end
      if k == '<Backspace>' then
        if #path == 0 then show('') return used end
        path[#path] = nil
        node = resolve(root, path)
      elseif k == '<Enter>' and node.run and not node.keys['<Enter>'] then
        local nxt = node.run()
        if type(nxt) == 'table' then node, buf = nxt, nil else return used end
      else
        local nxt = node.keys[k]
        if not nxt then
          show(trail() .. ' ' .. M.keyname(k) .. ' is not a shortcut  (' .. label .. ' ? lists them)')
          return used
        end
        path[#path + 1] = k
        node = nxt
      end
    elseif node.run then
      local nxt = node.run()
      if type(nxt) == 'table' then node, buf = nxt, nil else return used end
    else
      return used
    end
  end
end

-- map `key` in `mode` to the tree or step `spec`, globally
local function raw_keys(key)
  if key == '<Space>' then return { ' ', '<Space>' } end
  return { key }
end

function M.map(mode, key, spec, help)
  local label = M.keyname(key)
  local ok = true
  for _, k in ipairs(raw_keys(key)) do
    ok = vis:map(mode, k, function(keys) return M.drive(spec, label, keys) end, help) and ok
  end
  return ok
end

-- the same for one window
function M.map_window(win, mode, key, spec, help)
  local label = M.keyname(key)
  local ok = true
  for _, k in ipairs(raw_keys(key)) do
    ok = win:map(mode, k, function(keys) return M.drive(spec, label, keys) end, help) and ok
  end
  return ok
end

-- a step: a prompt for a line of text
function M.prompt(label, default, apply)
  return { prompt = label, default = default, apply = apply }
end

-- a step: one key out of a list of choices
function M.pick(title, options, apply)
  return { title = title, pick = options, apply = apply }
end

-- every action in a tree as rows for the cheat sheet: { keys = 'Space o a d', help = ..., group = ... }
function M.rows(root, label)
  local out = {}
  local function walk(node, trail, group)
    for _, k in ipairs(sorted_keys(node)) do
      local child = node.keys[k]
      if not child.hidden then
      local keys = trail .. ' ' .. M.keyname(k)
      if child.keys then
        if child.run and child.help then out[#out + 1] = { keys = keys .. ' Enter', help = child.help, group = group } end
        walk(child, keys, child.name or group)
      else
        out[#out + 1] = { keys = keys, help = child.help or '', group = group }
      end
      end
    end
  end
  walk(root, label, root.name or label)
  return out
end

return M
