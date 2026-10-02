-- The QR export view (kit/qrview.lua writes the file). The whole buffer is
-- forced to black on a true-white background: the half-block glyphs then draw
-- as standard dark-on-light modules on any theme, which is the only polarity
-- every QR Bridge receiver is proven to read. One tag, one style; the theme
-- sets STYLE_QR to black-on-white and ignores the palette here on purpose.
local lexer = lexer

local lex = lexer.new(..., { no_user_word_lists = true })

lex:add_rule('cell', lex:tag('QR', lexer.nonnewline^1))

return lex
