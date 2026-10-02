-- kit/export.lua - the QR Bridge chunk protocol, ported byte-for-byte from the
-- shipped tilde-shell sender (src/export.rs) and its cross-app contract
-- (docs/qr-export-plan.md). This is what lets a note leave a box: the text is
-- split into self-describing chunks, each shown as one QR by kit/qr.lua, and
-- the QR Bridge app's "Bridge transfer" mode reassembles them byte-exact.
--
-- Wire format, one string per QR:   ~1|<id>|<seq>/<total>|<crc>|<payload>
--   ~1       magic + format version; a scanned QR without it is not ours
--   <id>     8 hex, CRC32 of the whole text; groups one transfer
--   <seq>    1-based chunk index
--   <total>  chunk count
--   <crc>    8 hex, CRC32 of this chunk's payload (catches a mangled scan)
--   <payload>a contiguous slice; payloads concatenate back in seq order
--
-- Nothing here is editor-specific, so it is tested standalone against the
-- Rust reference's own vectors. Must stay in lock-step with the app; do not
-- "improve" the format without changing the receiver too.

local M = {}

local MAGIC = '~1'
local CHUNK_BYTES = 200 -- default payload budget when no terminal is in hand

-- DENSO byte-mode capacities at EC level L, versions 1..20 (the ceiling never
-- needs more). Same table as kit/qr.lua and src/export.rs.
local QR_CAP_L = {
	17, 32, 53, 78, 106, 134, 154, 192, 230, 271,
	321, 367, 425, 458, 520, 586, 644, 718, 792, 858,
}
local HEADER_BUDGET = 34   -- worst-case `~1|id|seq/total|crc|`
local BUDGET_FLOOR = 64    -- below this a transfer is confetti; refuse
local BUDGET_CEILING = 800 -- above this screen-to-camera scanning degrades

-- Standard CRC-32 (IEEE, polynomial 0xEDB88320). Check values:
--   crc32('123456789') == 0xcbf43926,  crc32('') == 0.
function M.crc32(s)
	local crc = 0xFFFFFFFF
	for i = 1, #s do
		crc = crc ~ s:byte(i)
		for _ = 1, 8 do
			local mask = -(crc & 1) -- 0 or all-ones in two's complement
			crc = (crc >> 1) ~ (0xEDB88320 & mask)
		end
	end
	return (~crc) & 0xFFFFFFFF
end

local function hex8(n) return string.format('%08x', n) end

-- Split `text` into pieces no larger than `max_bytes`, preferring a newline
-- boundary in the last half of the budget, else a UTF-8-safe byte boundary,
-- never cutting a codepoint and never splitting a CRLF pair. Byte-for-byte the
-- Rust `split_payloads`, so the web sender, tilde-shell and this kit chunk the
-- same input identically. Empty input yields one empty piece.
local function split_payloads(text, max_bytes)
	local len = #text
	if len == 0 then return { '' } end
	local function b(i) return text:byte(i + 1) end -- 0-indexed byte
	local out = {}
	local offset = 0
	while offset < len do
		local e = math.min(offset + max_bytes, len)
		if e < len then
			local min_pos = offset + (max_bytes // 2)
			local nl = e - 1
			while nl > min_pos and b(nl) ~= 10 do nl = nl - 1 end
			if b(nl) == 10 then
				e = nl + 1 -- keep the newline as the chunk's last byte
			else
				while e > offset and (b(e) & 0xC0) == 0x80 do e = e - 1 end
				if e > offset + 1 and b(e - 1) == 13 and b(e) == 10 then e = e - 1 end
			end
		end
		out[#out + 1] = text:sub(offset + 1, e)
		offset = e
	end
	return out
end
M.split_payloads = split_payloads

-- Split a rendered text into QR chunks with an explicit per-chunk payload
-- budget. Always at least one chunk, so an empty note still makes a valid 1/1.
function M.chunk_with_budget(text, max_bytes)
	local id = hex8(M.crc32(text))
	local payloads = split_payloads(text, math.max(max_bytes, 5))
	local total = #payloads
	local out = {}
	for i, payload in ipairs(payloads) do
		out[i] = string.format('%s|%s|%d/%d|%s|%s', MAGIC, id, i, total, hex8(M.crc32(payload)), payload)
	end
	return out
end

-- `chunk_with_budget` with the fixed default budget.
function M.chunk(text) return M.chunk_with_budget(text, CHUNK_BYTES) end

-- Per-chunk payload budget and the largest QR version a `cols` x `rows`
-- terminal can host (half-block cells carry two modules per row; the frame,
-- caption and status rows and a 4-module quiet zone cost the margins), or nil
-- when even the floor will not fit (roughly 47x27 and up works). Same math as
-- the Rust `budget_for_terminal`.
function M.budget_for_terminal(cols, rows)
	local m = math.min(math.max(cols - 2, 0), 2 * math.max(rows - 4, 0)) - 8
	if m < 21 then return nil end
	local v = math.min((m - 17) // 4, #QR_CAP_L)
	if v < 1 then return nil end
	local budget = math.min(QR_CAP_L[v] - HEADER_BUDGET, BUDGET_CEILING)
	if budget >= BUDGET_FLOOR then return budget, v end
	return nil
end

M.BUDGET_FLOOR = BUDGET_FLOOR
M.BUDGET_CEILING = BUDGET_CEILING

-- Parse one chunk into id, seq, total, crc, payload (five fields; the payload
-- keeps any `|` and newlines it contains). nil on bad magic or header.
local function parse_chunk(raw)
	local magic, id, seqtot, crc, payload =
		raw:match('^([^|]*)|([^|]*)|([^|]*)|([^|]*)|(.*)$')
	if magic ~= MAGIC then return nil end
	local seq, total = seqtot:match('^(%d+)/(%d+)$')
	if not seq then return nil end
	return id, tonumber(seq), tonumber(total), crc, payload
end
M.parse_chunk = parse_chunk

-- Reassemble chunks back into the original text: the inverse of chunk, and the
-- reference for what the receiver does. Verifies each payload's CRC, rejects a
-- mix of transfer ids or totals, concatenates in seq order once complete.
-- nil on a bad chunk, a CRC mismatch, mixed transfers, or a missing chunk.
function M.reassemble(chunks)
	local id, total
	local held = {}
	for _, raw in ipairs(chunks) do
		local cid, seq, tot, crc, payload = parse_chunk(raw)
		if not cid then return nil end
		if hex8(M.crc32(payload)) ~= crc then return nil end
		if id == nil then id = cid elseif id ~= cid then return nil end
		if total == nil then total = tot elseif total ~= tot then return nil end
		held[seq] = payload
	end
	if not total then return nil end
	local parts = {}
	for s = 1, total do
		if held[s] == nil then return nil end
		parts[s] = held[s]
	end
	return table.concat(parts)
end

return M
