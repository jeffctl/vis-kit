-- kit/qrview.lua: send the current file off the box as QR codes. Space Q (or
-- :qr) freezes the file's text, splits it into QR Bridge chunks (kit/export),
-- and shows one code at a time (kit/qr) in a side window. Scan them with the
-- QR Bridge app's "Bridge transfer" mode and it rebuilds the file on your
-- phone, verified chunk by chunk, with no network in between.
--
-- The chunk set is frozen when the view opens: the receiver buckets a scan by
-- the transfer id, so re-chunking mid-scan would orphan it. Resized the
-- terminal? press r to regenerate at the new size (a new transfer; restart the
-- scan on the phone).
local util = require('kit/util')
local export = require('kit/export')
local qr = require('kit/qr')

local M = {}

M.path = util.cache_dir() .. '/export.qrview'

-- One export at a time. nil when the view is closed.
--   { text, source, chunks, total, cur, budget, maxver, pending, warn }
local S = nil

function M.is_view(win)
	local p = win and win.file and win.file.path
	return p ~= nil and (p == M.path or p:match('/export%.qrview$') ~= nil)
end

local function view_window()
	for win in vis:windows() do
		if M.is_view(win) then return win end
	end
end

-- Current terminal text bytes of a window: the live buffer, so unsaved edits
-- are included. Falls back to the file size API shape on either vis build.
local function buffer_text(win)
	local file = win and win.file
	if not file then return '' end
	local size = file.size or 0
	if size <= 0 then return '' end
	local ok, content = pcall(function() return file:content(0, size) end)
	if ok and type(content) == 'string' then return content end
	return ''
end

local function write_and_show(win, lines)
	util.write_lines(M.path, lines)
	if vis.win ~= win then vis.win = win end
	vis:command('e!')
	-- a reload resets window options; keep the view clean so the quiet zone
	-- is real white and nothing shifts the code
	util.wopt(win, 'numbers', false)
	util.wopt(win, 'relativenumbers', false)
	util.wopt(win, 'cursorline', false)
	if vis.win.selection then vis.win.selection:to(1, 1) end
	if type(vis.redraw) == 'function' then vis:redraw() end
end

-- The "too small / nothing yet" placeholder (no chunks drawn).
local function render_message(win, body)
	local lines = { '' }
	for _, l in ipairs(body) do lines[#lines + 1] = l end
	write_and_show(win, lines)
end

-- Draw the current chunk.
local function render()
	local win = view_window()
	if not win or not S then return end
	if not S.chunks then return end
	local chunk = S.chunks[S.cur]
	local matrix, ver = qr.encode(chunk)
	local lines = {}
	for _, ln in ipairs(qr.render(matrix)) do lines[#lines + 1] = ln end
	-- short, fixed lines so nothing wraps in a narrow split; the bottom quiet
	-- zone already separates them from the code. The source name is clipped.
	local src = #S.source > 20 and (S.source:sub(1, 19) .. '…') or S.source
	local note = S.warn and '  re-chunked — restart the scan on your phone' or
		('  chunk %d/%d · v%d · %d B · %s'):format(S.cur, S.total, ver, #chunk, src)
	lines[#lines + 1] = note
	lines[#lines + 1] = '  type a number then Enter to jump to it'
	lines[#lines + 1] = '  l/h step · r re-chunk · q close'
	write_and_show(win, lines)
	S.warn = false
end
M.render = render

-- Compute the budget for the view window and split the text (a new transfer).
local function rechunk(win)
	win = win or view_window()
	if not win or not S then return end
	local vp = win.viewport
	local cols = (vp and vp.width) or 80
	local rows = (vp and vp.height) or 24
	local budget, maxver = export.budget_for_terminal(cols, rows)
	if not budget then
		S.chunks = nil
		render_message(win, {
			'  This window is a little small for a QR code.',
			'',
			'  Make it wider (fullscreen helps), then press  r  to try again.',
			'  About 47 columns by 27 rows is the floor; wider means fewer codes.',
			'',
			'  q  close',
		})
		return
	end
	S.chunks = export.chunk_with_budget(S.text, budget)
	S.total = #S.chunks
	S.budget, S.maxver = budget, maxver
	if S.cur > S.total then S.cur = S.total end
	if S.cur < 1 then S.cur = 1 end
	render()
	if S.total > 60 then
		vis:info(('%d codes — a wider terminal would make fewer'):format(S.total))
	end
end

-- Space Q / :qr - open the export view for the current file.
function M.show()
	local win = vis.win
	if M.is_view(win) then return end
	local file = win and win.file
	if not file then vis:info('qr: no file here to send'); return end
	local text = buffer_text(win)
	if text == '' then vis:info('qr: nothing to send (the file is empty)'); return end
	util.save(win) -- raw export is the bytes on disk; save first so they match
	local src = (file.path and util.basename(file.path)) or '(unsaved)'
	S = { text = text, source = src, cur = 1, pending = '', warn = false }

	local existing = view_window()
	if existing then
		vis.win = existing
		rechunk(existing)
	else
		util.write_lines(M.path, { '', '  preparing the QR export…', '' })
		vis:command('vsplit ' .. util.cmd_escape(M.path))
		-- WIN_OPEN installs the keys; draw once the split exists and is sized.
		rechunk(view_window())
	end
end

local function go(n)
	if not S or not S.chunks then return end
	S.cur = math.max(1, math.min(n, S.total))
	S.pending = ''
	vis:info('')
	render()
end

local function close(win)
	S = nil
	vis:info('')
	local n = 0
	for _ in vis:windows() do n = n + 1 end
	if n <= 1 then vis:command('q') else win:close(true) end
end
M.close = close

-- The view's keys. `leader` is unused today but kept for the install signature
-- the other kit windows share.
function M.install(win, leader)
	local N = vis.modes.NORMAL
	local function map(key, fn, help) win:map(N, key, fn, help) end

	map('l', function() if S then go(S.cur + 1) end end, 'Next code')
	map('<Space>', function() if S then go(S.cur + 1) end end, 'Next code')
	map('<Right>', function() if S then go(S.cur + 1) end end, 'Next code')
	map('j', function() if S then go(S.cur + 1) end end, 'Next code')
	map('h', function() if S then go(S.cur - 1) end end, 'Previous code')
	map('<Left>', function() if S then go(S.cur - 1) end end, 'Previous code')
	map('k', function() if S then go(S.cur - 1) end end, 'Previous code')
	map('<Home>', function() if S then go(1) end end, 'First code')
	map('<End>', function() if S then go(S.total) end end, 'Last code')

	for d = 0, 9 do
		map(tostring(d), function()
			if not S or not S.chunks then return end
			S.pending = S.pending .. tostring(d)
			vis:info(('go to chunk %s  —  Enter jumps, Esc clears'):format(S.pending))
		end, 'Type a chunk number')
	end
	map('<Enter>', function()
		if not S then return end
		if S.pending ~= '' then go(tonumber(S.pending) or S.cur) else go(S.cur + 1) end
	end, 'Jump to the typed number (or next)')
	map('<Backspace>', function()
		if not S then return end
		S.pending = S.pending:sub(1, #S.pending - 1)
		vis:info(S.pending == '' and '' or ('go to chunk ' .. S.pending))
	end, 'Erase a digit')
	map('<Escape>', function()
		if S and S.pending ~= '' then
			S.pending = ''; vis:info('')
		else
			close(win)
		end
	end, 'Clear the number, or close')

	map('r', function()
		if not S then return end
		S.pending = ''; S.warn = true
		rechunk(win)
	end, 'Re-chunk at this size (new transfer)')
	map('q', function() close(win) end, 'Close the QR export')
	map('<C-c>', function() close(win) end, 'Close the QR export')
end

return M
