-- kit/qr.lua - a tiny byte-mode QR encoder and a terminal renderer, pure Lua,
-- no dependencies, no shelling out. Enough to show one chunk of text as a
-- scannable code on any box, so a report can leave an air-gapped machine
-- through the QR Bridge app and land on a phone as plain text.
--
-- Scope: byte mode, error-correction level L, versions 1..20 (the chunk
-- budget never needs more). The smallest version that holds the payload is
-- chosen per code. The matrix this builds is standard; it is verified against
-- a reference encoder (segno) and a real scanner (zbar) in the test harness.
--
-- Why pure Lua and not `qrencode`: the boxes that most need this (locked down,
-- no root, no package manager, no network) are exactly the ones where no QR
-- tool is installed. The kit carries its own.

local M = {}

-- ---------------------------------------------------------------------------
-- GF(256) arithmetic for Reed-Solomon, primitive polynomial 0x11d, gen 2.
-- ---------------------------------------------------------------------------
local EXP, LOG = {}, {}
do
	local x = 1
	for i = 0, 255 do
		EXP[i] = x
		LOG[x] = i
		x = x << 1
		if x & 0x100 ~= 0 then x = x ~ 0x11d end
	end
	-- EXP wraps so we can index 0..509 without a modulo in the hot loop.
	for i = 256, 511 do EXP[i] = EXP[i - 255] end
end

local function gf_mul(a, b)
	if a == 0 or b == 0 then return 0 end
	return EXP[LOG[a] + LOG[b]]
end

-- Reed-Solomon generator polynomial of the given degree (number of EC
-- codewords), coefficients high-order first.
local function rs_generator(degree)
	local g = { 1 }
	for i = 0, degree - 1 do
		-- multiply g(x) by (x - a^i)
		local ng = {}
		for j = 1, #g do ng[j] = g[j] end
		ng[#g + 1] = 0
		local factor = EXP[i]
		for j = 1, #g do
			ng[j + 1] = ng[j + 1] ~ gf_mul(g[j], factor)
		end
		g = ng
	end
	return g
end

-- EC codewords for one data block.
local function rs_encode(data, ec_count)
	local gen = rs_generator(ec_count)
	local res = {}
	for i = 1, ec_count do res[i] = 0 end
	for i = 1, #data do
		local factor = data[i] ~ res[1]
		table.remove(res, 1)
		res[ec_count] = 0
		if factor ~= 0 then
			local lf = LOG[factor]
			for j = 1, ec_count do
				res[j] = res[j] ~ EXP[lf + LOG[gen[j + 1]]]
			end
		end
	end
	return res
end

-- ---------------------------------------------------------------------------
-- Per-version tables, EC level L, versions 1..20.
-- ---------------------------------------------------------------------------
-- {ec_codewords_per_block, {blocks_g1, data_g1}[, {blocks_g2, data_g2}]}
local BLOCKS_L = {
	{ 7, { 1, 19 } },
	{ 10, { 1, 34 } },
	{ 15, { 1, 55 } },
	{ 20, { 1, 80 } },
	{ 26, { 1, 108 } },
	{ 18, { 2, 68 } },
	{ 20, { 2, 78 } },
	{ 24, { 2, 97 } },
	{ 30, { 2, 116 } },
	{ 18, { 2, 68 }, { 2, 69 } },
	{ 20, { 4, 81 } },
	{ 24, { 2, 92 }, { 2, 93 } },
	{ 26, { 4, 107 } },
	{ 30, { 3, 115 }, { 1, 116 } },
	{ 22, { 5, 87 }, { 1, 88 } },
	{ 24, { 5, 98 }, { 1, 99 } },
	{ 28, { 1, 107 }, { 5, 108 } },
	{ 30, { 5, 120 }, { 1, 121 } },
	{ 28, { 3, 113 }, { 4, 114 } },
	{ 28, { 3, 107 }, { 5, 108 } },
}

-- Alignment pattern centre coordinates per version (none for v1).
local ALIGN = {
	{}, { 6, 18 }, { 6, 22 }, { 6, 26 }, { 6, 30 }, { 6, 34 },
	{ 6, 22, 38 }, { 6, 24, 42 }, { 6, 26, 46 }, { 6, 28, 50 }, { 6, 30, 54 },
	{ 6, 32, 58 }, { 6, 34, 62 }, { 6, 26, 46, 66 }, { 6, 26, 48, 70 },
	{ 6, 26, 50, 74 }, { 6, 30, 54, 78 }, { 6, 30, 56, 82 }, { 6, 30, 58, 86 },
	{ 6, 34, 62, 90 },
}

-- Remainder bits appended after the final codeword, per version.
local REMAINDER = { 0, 7, 7, 7, 7, 7, 0, 0, 0, 0, 0, 0, 0, 3, 3, 3, 3, 3, 3, 3 }

-- Total data codewords for a version (sum over its blocks).
local function data_codewords(v)
	local b = BLOCKS_L[v]
	local n = b[2][1] * b[2][2]
	if b[3] then n = n + b[3][1] * b[3][2] end
	return n
end

-- Byte-mode character-count indicator is 8 bits for v1..9, else 16.
local function count_bits(v) return v <= 9 and 8 or 16 end

-- Smallest version 1..20 whose data capacity holds `n` payload bytes in byte
-- mode at EC L, or nil if none does (n beyond v20's ~858 B).
function M.fit_version(n)
	for v = 1, 20 do
		local bits = 4 + count_bits(v) + 8 * n
		if bits <= data_codewords(v) * 8 then return v end
	end
	return nil
end

-- ---------------------------------------------------------------------------
-- Bit buffer.
-- ---------------------------------------------------------------------------
local function new_bits()
	return { bytes = {}, nbits = 0 }
end

local function push_bits(buf, value, len)
	for i = len - 1, 0, -1 do
		local bit = (value >> i) & 1
		local pos = buf.nbits
		local byte_idx = (pos >> 3) + 1
		if pos & 7 == 0 then buf.bytes[byte_idx] = 0 end
		if bit == 1 then
			buf.bytes[byte_idx] = buf.bytes[byte_idx] | (1 << (7 - (pos & 7)))
		end
		buf.nbits = pos + 1
	end
end

-- ---------------------------------------------------------------------------
-- Encode a string to a matrix of 0/1 (1 = dark). Returns matrix (0-indexed
-- rows/cols as Lua tables with keys 0..size-1) and the version used.
-- ---------------------------------------------------------------------------

-- Data codewords (with mode, count, terminator, pad) for text at version v.
local function build_codewords(text, v)
	local buf = new_bits()
	push_bits(buf, 0x4, 4)                   -- byte mode indicator
	push_bits(buf, #text, count_bits(v))     -- character count
	for i = 1, #text do push_bits(buf, text:byte(i), 8) end

	local cap = data_codewords(v) * 8
	-- terminator: up to four zero bits
	local term = math.min(4, cap - buf.nbits)
	if term > 0 then push_bits(buf, 0, term) end
	-- pad to a byte boundary
	if buf.nbits & 7 ~= 0 then push_bits(buf, 0, 8 - (buf.nbits & 7)) end
	-- pad bytes 0xEC, 0x11 alternating
	local pad = { 0xEC, 0x11 }
	local pi = 1
	while buf.nbits < cap do
		push_bits(buf, pad[pi], 8)
		pi = pi == 1 and 2 or 1
	end

	local cw = {}
	for i = 1, #buf.bytes do cw[i] = buf.bytes[i] end
	-- ensure full count (trailing zero byte if the last push was short)
	while #cw < data_codewords(v) do cw[#cw + 1] = 0 end
	return cw
end

-- Split data codewords into blocks, compute EC, interleave to the final stream.
local function interleave(cw, v)
	local b = BLOCKS_L[v]
	local ec_per = b[1]
	local specs = { b[2] }
	if b[3] then specs[2] = b[3] end

	local data_blocks, ec_blocks = {}, {}
	local idx = 1
	for _, spec in ipairs(specs) do
		for _ = 1, spec[1] do
			local block = {}
			for _ = 1, spec[2] do
				block[#block + 1] = cw[idx]
				idx = idx + 1
			end
			data_blocks[#data_blocks + 1] = block
			ec_blocks[#ec_blocks + 1] = rs_encode(block, ec_per)
		end
	end

	local out = {}
	-- data codewords, column by column across blocks
	local maxdata = 0
	for _, blk in ipairs(data_blocks) do if #blk > maxdata then maxdata = #blk end end
	for i = 1, maxdata do
		for _, blk in ipairs(data_blocks) do
			if blk[i] then out[#out + 1] = blk[i] end
		end
	end
	-- EC codewords, column by column (all equal length)
	for i = 1, ec_per do
		for _, blk in ipairs(ec_blocks) do
			out[#out + 1] = blk[i]
		end
	end
	return out
end

-- Matrix helpers (0-indexed).
local function new_matrix(size)
	local m, fixed = {}, {}
	for r = 0, size - 1 do
		m[r], fixed[r] = {}, {}
		for c = 0, size - 1 do m[r][c] = 0; fixed[r][c] = false end
	end
	return m, fixed
end

local function place_finder(m, fixed, size, r0, c0)
	for dr = -1, 7 do
		for dc = -1, 7 do
			local r, c = r0 + dr, c0 + dc
			if r >= 0 and r < size and c >= 0 and c < size then
				local dark
				if dr >= 0 and dr <= 6 and dc >= 0 and dc <= 6 then
					dark = (dr == 0 or dr == 6 or dc == 0 or dc == 6
						or (dr >= 2 and dr <= 4 and dc >= 2 and dc <= 4))
				else
					dark = false -- separator ring
				end
				m[r][c] = dark and 1 or 0
				fixed[r][c] = true
			end
		end
	end
end

local function place_alignment(m, fixed, size, centres)
	for _, r in ipairs(centres) do
		for _, c in ipairs(centres) do
			-- skip the three that collide with finder patterns
			local on_finder = (r == 6 and c == 6)
				or (r == 6 and c == size - 7)
				or (r == size - 7 and c == 6)
			if not on_finder then
				for dr = -2, 2 do
					for dc = -2, 2 do
						local dark = (dr == -2 or dr == 2 or dc == -2 or dc == 2
							or (dr == 0 and dc == 0))
						m[r + dr][c + dc] = dark and 1 or 0
						fixed[r + dr][c + dc] = true
					end
				end
			end
		end
	end
end

local function reserve_format(fixed, size)
	for i = 0, 8 do
		if i ~= 6 then fixed[8][i] = true; fixed[i][8] = true end
	end
	for i = 0, 7 do fixed[size - 1 - i][8] = true end
	for i = 0, 7 do fixed[8][size - 1 - i] = true end
	fixed[size - 8][8] = true -- dark module
end

local function reserve_version(fixed, size)
	for i = 0, 5 do
		for j = 0, 2 do
			fixed[size - 11 + j][i] = true
			fixed[i][size - 11 + j] = true
		end
	end
end

local function getbit(v, i) return (v >> i) & 1 end

local function draw_format(m, ec_mask_data, size)
	-- ec_mask_data is the 5-bit (ecl<<3 | mask); compute BCH(15,5).
	local rem = ec_mask_data
	for _ = 1, 10 do
		rem = (rem << 1) ~ (((rem >> 9) & 1) == 1 and 0x537 or 0)
	end
	local bits = ((ec_mask_data << 10) | rem) ~ 0x5412
	for i = 0, 5 do m[i][8] = getbit(bits, i) end
	m[7][8] = getbit(bits, 6)
	m[8][8] = getbit(bits, 7)
	m[8][7] = getbit(bits, 8)
	for i = 9, 14 do m[8][14 - i] = getbit(bits, i) end
	for i = 0, 7 do m[8][size - 1 - i] = getbit(bits, i) end
	for i = 8, 14 do m[size - 15 + i][8] = getbit(bits, i) end
	m[size - 8][8] = 1 -- always dark
end

local function draw_version(m, v, size)
	if v < 7 then return end
	local rem = v
	for _ = 1, 12 do
		rem = (rem << 1) ~ (((rem >> 11) & 1) == 1 and 0x1F25 or 0)
	end
	local bits = (v << 12) | rem
	for i = 0, 17 do
		local bit = getbit(bits, i)
		local a = size - 11 + (i % 3)
		local b = i // 3
		m[b][a] = bit
		m[a][b] = bit
	end
end

local function draw_timing(m, fixed, size)
	for i = 8, size - 9 do
		if not fixed[6][i] then m[6][i] = (i % 2 == 0) and 1 or 0; fixed[6][i] = true end
		if not fixed[i][6] then m[i][6] = (i % 2 == 0) and 1 or 0; fixed[i][6] = true end
	end
end

local function place_data(m, fixed, size, stream)
	local bitpos = 0
	local nbits = #stream * 8
	local function next_bit()
		if bitpos >= nbits then return 0 end -- remainder bits are 0
		local byte = stream[(bitpos >> 3) + 1]
		local bit = (byte >> (7 - (bitpos & 7))) & 1
		bitpos = bitpos + 1
		return bit
	end
	local upward = true
	local col = size - 1
	while col > 0 do
		if col == 6 then col = 5 end -- skip the vertical timing column
		for i = 0, size - 1 do
			local row = upward and (size - 1 - i) or i
			for _, c in ipairs({ col, col - 1 }) do
				if not fixed[row][c] then
					m[row][c] = next_bit()
				end
			end
		end
		col = col - 2
		upward = not upward
	end
end

local MASKS = {
	[0] = function(r, c) return (r + c) % 2 == 0 end,
	[1] = function(r, c) return r % 2 == 0 end,
	[2] = function(r, c) return c % 3 == 0 end,
	[3] = function(r, c) return (r + c) % 3 == 0 end,
	[4] = function(r, c) return (r // 2 + c // 3) % 2 == 0 end,
	[5] = function(r, c) return (r * c) % 2 + (r * c) % 3 == 0 end,
	[6] = function(r, c) return ((r * c) % 2 + (r * c) % 3) % 2 == 0 end,
	[7] = function(r, c) return ((r + c) % 2 + (r * c) % 3) % 2 == 0 end,
}

local function copy_matrix(m, size)
	local n = {}
	for r = 0, size - 1 do
		n[r] = {}
		for c = 0, size - 1 do n[r][c] = m[r][c] end
	end
	return n
end

-- Penalty score for mask selection (ISO/IEC 18004 rules N1..N4).
local function penalty(m, size)
	local score = 0
	-- N1: runs of five or more of the same colour, per row and per column.
	for r = 0, size - 1 do
		local run, prev = 1, -1
		for c = 0, size - 1 do
			if m[r][c] == prev then
				run = run + 1
			else
				if run >= 5 then score = score + 3 + (run - 5) end
				run, prev = 1, m[r][c]
			end
		end
		if run >= 5 then score = score + 3 + (run - 5) end
	end
	for c = 0, size - 1 do
		local run, prev = 1, -1
		for r = 0, size - 1 do
			if m[r][c] == prev then
				run = run + 1
			else
				if run >= 5 then score = score + 3 + (run - 5) end
				run, prev = 1, m[r][c]
			end
		end
		if run >= 5 then score = score + 3 + (run - 5) end
	end
	-- N2: 2x2 blocks of one colour.
	for r = 0, size - 2 do
		for c = 0, size - 2 do
			local v = m[r][c]
			if v == m[r][c + 1] and v == m[r + 1][c] and v == m[r + 1][c + 1] then
				score = score + 3
			end
		end
	end
	-- N3: the finder-like sequences 1011101-0000 and 0000-1011101 (dark 1,
	-- light 0), scanned as an 11-module window across every row and column.
	local function scan(get)
		local n = 0
		for a = 0, size - 1 do
			for b = 0, size - 11 do
				local w0, w1, w2, w3, w4, w5, w6, w7, w8, w9, w10 =
					get(a, b), get(a, b + 1), get(a, b + 2), get(a, b + 3),
					get(a, b + 4), get(a, b + 5), get(a, b + 6), get(a, b + 7),
					get(a, b + 8), get(a, b + 9), get(a, b + 10)
				if (w0 == 1 and w1 == 0 and w2 == 1 and w3 == 1 and w4 == 1
						and w5 == 0 and w6 == 1 and w7 == 0 and w8 == 0 and w9 == 0 and w10 == 0)
					or (w0 == 0 and w1 == 0 and w2 == 0 and w3 == 0 and w4 == 1 and w5 == 0
						and w6 == 1 and w7 == 1 and w8 == 1 and w9 == 0 and w10 == 1) then
					n = n + 1
				end
			end
		end
		return n
	end
	local n3 = scan(function(a, b) return m[a][b] end)
		+ scan(function(a, b) return m[b][a] end)
	score = score + n3 * 40
	-- N4: deviation of the dark-module proportion from 50%.
	local dark = 0
	for r = 0, size - 1 do
		for c = 0, size - 1 do dark = dark + m[r][c] end
	end
	local total = size * size
	local percent = dark * 100 / total
	local lower = math.floor(percent / 5) * 5
	local upper = lower + 5
	local k = math.min(math.abs(lower - 50), math.abs(upper - 50)) / 5
	score = score + math.floor(k) * 10
	return score
end

-- Build the final matrix for `text`. Chooses the smallest fitting version.
function M.encode(text)
	local v = M.fit_version(#text)
	if not v then error('qr: payload too large for v20 (' .. #text .. ' bytes)') end
	local size = 17 + 4 * v

	local base, fixed = new_matrix(size)
	place_finder(base, fixed, size, 0, 0)
	place_finder(base, fixed, size, 0, size - 7)
	place_finder(base, fixed, size, size - 7, 0)
	place_alignment(base, fixed, size, ALIGN[v])
	draw_timing(base, fixed, size)
	reserve_format(fixed, size)
	if v >= 7 then reserve_version(fixed, size) end
	base[size - 8][8] = 1; fixed[size - 8][8] = true -- dark module

	local cw = build_codewords(text, v)
	local stream = interleave(cw, v)
	place_data(base, fixed, size, stream)
	draw_version(base, v, size)

	local best, best_score
	for mask = 0, 7 do
		local cand = copy_matrix(base, size)
		local mf = MASKS[mask]
		for r = 0, size - 1 do
			for c = 0, size - 1 do
				if not fixed[r][c] and mf(r, c) then cand[r][c] = cand[r][c] ~ 1 end
			end
		end
		draw_format(cand, (0x01 << 3) | mask, size) -- EC level L = 0b01
		local s = penalty(cand, size)
		if not best_score or s < best_score then best, best_score = cand, s end
	end
	return best, v
end

-- ---------------------------------------------------------------------------
-- Terminal rendering: half blocks, a 4-module quiet zone, forced dark-on-light
-- (the only polarity every QR Bridge receiver is proven to read). The kit's
-- qr lexer paints every glyph black on white, so this scans on any theme.
-- ---------------------------------------------------------------------------
local QUIET = 4

-- Returns a list of text lines. Each line is a row of half-block cells; one
-- cell stacks two vertical modules (top = foreground, bottom = background).
function M.render(matrix)
	local size = #matrix + 1 -- matrix is 0-indexed 0..size-1
	local function dark(r, c)
		-- outside the matrix (quiet zone) is light
		if r < 0 or c < 0 or r >= size or c >= size then return false end
		return matrix[r][c] == 1
	end
	local lines = {}
	-- rows run from -QUIET to size-1+QUIET; step two for half blocks
	local top = -QUIET
	local bottom_limit = size - 1 + QUIET
	while top <= bottom_limit do
		local parts = {}
		for c = -QUIET, size - 1 + QUIET do
			local t = dark(top, c)
			local b = dark(top + 1, c)
			local glyph
			if t and b then glyph = '\u{2588}'      -- full block
			elseif t then glyph = '\u{2580}'         -- upper half
			elseif b then glyph = '\u{2584}'         -- lower half
			else glyph = ' ' end
			parts[#parts + 1] = glyph
		end
		lines[#lines + 1] = table.concat(parts)
		top = top + 2
	end
	return lines
end

-- Width in terminal columns of a rendered code for a given version (includes
-- the quiet zone), so the UI can centre it.
function M.width(v) return 17 + 4 * v + 2 * QUIET end

return M
