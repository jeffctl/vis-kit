-- Org LPeg lexer for vis. Headings by level, the kit's TODO states, planning
-- lines (SCHEDULED: / DEADLINE: / CLOSED:) and time stamps, drawers, tags,
-- priorities, checkboxes, list bullets, links, *bold* /italic/ _underline_
-- +strike+ ~code~ =verbatim=, #+ lines and # comments. The states match
-- kit/org.lua. vis 0.9 ships no org lexer; newer builds ship one whose date
-- rules never match, and this one is found first. MIT, see LICENSE.
local lexer = lexer
local P, S, R, B = lpeg.P, lpeg.S, lpeg.R, lpeg.B

local lex = lexer.new(..., { no_user_word_lists = true })

local nonnl = lexer.nonnewline
local hspace = S(' \t')
local eol = #(hspace^0 * (lexer.newline + P(-1)))
local alnum = R('AZ', 'az', '09')

-- # comments and #+ lines (titles, BEGIN / END of blocks)
lex:add_rule('comment', lex:tag('comment', lexer.starts_line(lexer.to_eol('# '), true)))
lex:add_rule('block', lex:tag('BLOCK', lexer.starts_line(lexer.to_eol('#+'), true)))

-- the stars carry the level color; the rest of the line goes through the rules below
local function h(n)
  return lex:tag('heading.h' .. n, lexer.starts_line(P(string.rep('*', n)) * ' '))
end
lex:add_rule('heading', h(6) + h(5) + h(4) + h(3) + h(2) + h(1))

-- SCHEDULED: <2026-10-05 Sun>, and drawers (:PROPERTIES: ... :END:, :LOGBOOK:)
lex:add_rule('planning', lex:tag('PLANNING', P('SCHEDULED:') + 'DEADLINE:' + 'CLOSED:'))
lex:add_rule('drawer', lex:tag('DRAWER',
  lexer.starts_line(lexer.to_eol(':' * (alnum + '_')^1 * ':'), true)))

-- states
local function words(tag, list)
  return lex:tag(tag, lexer.word_match(list))
end
lex:add_rule('todo', words('TODO', { 'TODO' }))
lex:add_rule('inprogress', words('INPROGRESS', { 'INPROGRESS' }))
lex:add_rule('waiting', words('WAITING', { 'WAITING' }))
lex:add_rule('blocked', words('BLOCKED', { 'BLOCKED' }))
lex:add_rule('scheduled_kw', words('SCHEDULED_KW', { 'SCHEDULED' }))
lex:add_rule('deferred', words('DEFERRED', { 'DEFERRED' }))
lex:add_rule('someday', words('SOMEDAY', { 'SOMEDAY' }))
lex:add_rule('done', words('DONE', { 'DONE' }))
lex:add_rule('delegated', words('DELEGATED', { 'DELEGATED' }))
lex:add_rule('cancelled', words('CANCELLED', { 'CANCELLED' }))

-- [#A] priorities, [ ] / [X] checkboxes
lex:add_rule('priority', lex:tag('PRIORITY_A', P('[#A]')) + lex:tag('PRIORITY', '[#' * R('BF') * ']'))
lex:add_rule('checkbox', lex:tag('CHECKBOX_DONE', P('[X]') + '[x]') + lex:tag('CHECKBOX', P('[ ]') + '[-]'))

-- a rule across (-----), list bullets
lex:add_rule('hr', lex:tag('hr', lexer.starts_line(P('-')^5 * eol)))
lex:add_rule('list', lex:tag('list',
  lexer.starts_line((S('-+*') + lexer.digit^1 * S('.)')) * #P(' '), true)))

-- <2026-10-05 Sun 10:00 +1w> and [2026-10-02 Thu]
local date = lexer.digit * lexer.digit * lexer.digit * lexer.digit * '-' * lexer.digit * lexer.digit * '-' * lexer.digit * lexer.digit
lex:add_rule('date', lex:tag('DATE', '<' * date * (nonnl - '>')^0 * '>'))
lex:add_rule('date_inactive', lex:tag('DATE_INACTIVE', '[' * date * (nonnl - ']')^0 * ']'))

-- [[link][description]]
lex:add_rule('link', lex:tag('link',
  '[[' * (nonnl - ']')^1 * ']' * ('[' * (nonnl - ']')^0 * ']')^-1 * ']'))

-- :tags: at the end of a heading
local tagword = (alnum + S('_@#%'))^1
lex:add_rule('tag', lex:tag('TAG', ':' * tagword * (':' * tagword)^0 * ':' * eol))

-- *bold* /italic/ _underline_ +strike+ ~code~ =verbatim=, one line each,
-- not inside a word (so a_snake_case name or a /path/to/file stays plain)
local function markup(tag, ch)
  local inner = nonnl - ch
  return lex:tag(tag, -B(alnum + S('/_~=+*')) * P(ch) * (inner - hspace) * inner^0 * ch * -(alnum))
end
lex:add_rule('bold', markup('BOLD', '*'))
lex:add_rule('italic', markup('ITALIC', '/'))
lex:add_rule('underline', markup('UNDERLINE', '_'))
lex:add_rule('strike', markup('STRIKE', '+'))
lex:add_rule('code', markup('code', '~') + markup('code', '='))

return lex
