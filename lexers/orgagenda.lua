-- The agenda's highlighting (kit/agenda.lua writes the file): section names,
-- the states, due / overdue / coming up words, times, priorities.
local lexer = lexer
local P, S, R = lpeg.P, lpeg.S, lpeg.R

local lex = lexer.new(..., { no_user_word_lists = true })

local nonnl = lexer.nonnewline

-- the first line (lowercase at the margin) is the key legend; a line in
-- capitals at the margin is a section or a day; a line of ─ is a rule
lex:add_rule('legend', lex:tag('LEGEND', lexer.starts_line(R('az') * nonnl^0)))
lex:add_rule('section', lex:tag('SECTION', lexer.starts_line(R('AZ') * nonnl^0)))
lex:add_rule('hr', lex:tag('hr', lexer.starts_line(P('─')^1)))

-- the "when" column
lex:add_rule('due', lex:tag('DUE', lexer.word_match({ 'due' })))
lex:add_rule('overdue', lex:tag('OVERDUE', lexer.digit^1 * 'd ago'))
lex:add_rule('soon', lex:tag('SOON', 'in ' * lexer.digit^1 * 'd'))
lex:add_rule('today', lex:tag('TODAY', lexer.word_match({ 'today' })))
lex:add_rule('since', lex:tag('SINCE', lexer.starts_line(lexer.digit^1 * 'd' * #P(' '), true)))
lex:add_rule('time', lex:tag('TIME', lexer.digit * lexer.digit * ':' * lexer.digit * lexer.digit))

-- states and priorities, as in lexers/org.lua
local function words(tag, list) return lex:tag(tag, lexer.word_match(list)) end
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
lex:add_rule('priority', lex:tag('PRIORITY_A', P('· A')) + lex:tag('PRIORITY', '· ' * R('BF')))

return lex
