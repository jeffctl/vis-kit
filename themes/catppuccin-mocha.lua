-- Catppuccin Mocha for vis, blue as the primary accent (the Neovim kit's
-- look). 24-bit colors: Ghostty, iTerm2, Windows Terminal, Apple's Terminal
-- from macOS 26, Termux and kitty all draw them; a 256-color terminal gets
-- the nearest shade. The style words vis knows: fore:, back:, bold, italics,
-- underlined, dim, reverse, keep_attribute.
local lexers = vis.lexers

local base, mantle = '#1e1e2e', '#181825'
local text, subtext0 = '#cdd6f4', '#a6adc8'
local overlay2, overlay1, overlay0 = '#9399b2', '#7f849c', '#6c7086'
local surface2, surface1, surface0 = '#585b70', '#45475a', '#313244'
local lavender, blue, sapphire, sky, teal = '#b4befe', '#89b4fa', '#74c7ec', '#89dceb', '#94e2d5'
local green, yellow, peach, maroon, red = '#a6e3a1', '#f9e2af', '#fab387', '#eba0ac', '#f38ba8'
local mauve, pink, flamingo, rosewater = '#cba6f7', '#f5c2e7', '#f2cdcd', '#f5e0dc'

local function fg(c, extra) return 'fore:' .. c .. (extra and (',' .. extra) or '') end

lexers.STYLE_DEFAULT = 'back:' .. base .. ',fore:' .. text
lexers.STYLE_NOTHING = ''
lexers.STYLE_ATTRIBUTE = fg(yellow)
lexers.STYLE_CLASS = fg(yellow)
lexers.STYLE_COMMENT = fg(overlay0, 'italics')
lexers.STYLE_CONSTANT = fg(peach)
lexers.STYLE_DEFINITION = fg(blue)
lexers.STYLE_ERROR = fg(red, 'italics')
lexers.STYLE_FUNCTION = fg(blue)
lexers.STYLE_HEADING = fg(mauve, 'bold')
lexers.STYLE_KEYWORD = fg(mauve)
lexers.STYLE_LABEL = fg(teal)
lexers.STYLE_NUMBER = fg(peach)
lexers.STYLE_OPERATOR = fg(sky)
lexers.STYLE_REGEX = fg(pink)
lexers.STYLE_STRING = fg(green)
lexers.STYLE_PREPROCESSOR = fg(pink)
lexers.STYLE_TAG = fg(blue)
lexers.STYLE_TYPE = fg(yellow)
lexers.STYLE_VARIABLE = fg(text)
lexers.STYLE_WHITESPACE = ''
lexers.STYLE_EMBEDDED = fg(pink)
lexers.STYLE_IDENTIFIER = ''

lexers.STYLE_LINENUMBER = fg(overlay0) .. ',back:' .. base
lexers.STYLE_LINENUMBER_CURSOR = fg(lavender, 'bold') .. ',back:' .. base
lexers.STYLE_CURSOR = 'back:' .. rosewater .. ',fore:' .. base
lexers.STYLE_CURSOR_PRIMARY = lexers.STYLE_CURSOR
lexers.STYLE_CURSOR_LINE = 'back:' .. surface0 .. ',keep_attribute'
lexers.STYLE_COLOR_COLUMN = 'back:' .. surface0
lexers.STYLE_SELECTION = 'back:' .. surface1 .. ',keep_attribute'
lexers.STYLE_STATUS = 'back:' .. mantle .. ',fore:' .. overlay1
lexers.STYLE_STATUS_FOCUSED = 'back:' .. blue .. ',fore:' .. base .. ',bold' -- kit/mode.lua recolors this per mode
lexers.STYLE_SEPARATOR = fg(surface1) .. ',back:' .. base
lexers.STYLE_INFO = fg(text, 'bold') .. ',back:' .. base
lexers.STYLE_EOF = fg(surface1)

-- Diff
lexers.STYLE_ADDITION = fg(green)
lexers.STYLE_DELETION = fg(red)
lexers.STYLE_CHANGE = fg(yellow)

-- Markdown and friends
lexers.STYLE_HR = fg(surface2)
lexers.STYLE_HEADING_H1 = fg(red, 'bold')
lexers.STYLE_HEADING_H2 = fg(peach, 'bold')
lexers.STYLE_HEADING_H3 = fg(yellow, 'bold')
lexers.STYLE_HEADING_H4 = fg(green, 'bold')
lexers.STYLE_HEADING_H5 = fg(sapphire, 'bold')
lexers.STYLE_HEADING_H6 = fg(lavender, 'bold')
lexers.STYLE_BOLD = 'bold'
lexers.STYLE_ITALIC = 'italics'
lexers.STYLE_UNDERLINE = 'underlined'
lexers.STYLE_STRIKE = fg(overlay1)
lexers.STYLE_LIST = fg(blue)
lexers.STYLE_LINK = fg(sapphire, 'underlined')
lexers.STYLE_REFERENCE = fg(sapphire)
lexers.STYLE_CODE = fg(flamingo) .. ',back:' .. surface0

-- Org (lexers/org.lua): the states, as the Neovim kit colors them
lexers.STYLE_TODO = fg(blue, 'bold')
lexers.STYLE_INPROGRESS = fg(teal, 'bold')
lexers.STYLE_WAITING = fg(lavender, 'bold')
lexers.STYLE_BLOCKED = fg(red, 'bold')
lexers.STYLE_SCHEDULED_KW = fg(sky, 'bold')
lexers.STYLE_DEFERRED = fg(overlay1)
lexers.STYLE_SOMEDAY = fg(mauve)
lexers.STYLE_DONE = fg(overlay1)
lexers.STYLE_DELEGATED = fg(green)
lexers.STYLE_CANCELLED = fg(overlay0)
lexers.STYLE_PLANNING = fg(overlay1, 'bold')
lexers.STYLE_DATE = fg(sky)
lexers.STYLE_DATE_INACTIVE = fg(overlay1)
lexers.STYLE_DRAWER = fg(overlay0)
lexers.STYLE_PRIORITY_A = fg(red, 'bold')
lexers.STYLE_PRIORITY = fg(peach, 'bold')
lexers.STYLE_CHECKBOX = fg(overlay2)
lexers.STYLE_CHECKBOX_DONE = fg(green)
lexers.STYLE_BLOCK = fg(overlay1)

-- The agenda (lexers/orgagenda.lua)
lexers.STYLE_SECTION = fg(blue, 'bold')
lexers.STYLE_LEGEND = fg(overlay0)
lexers.STYLE_DUE = fg(red, 'bold')
lexers.STYLE_OVERDUE = fg(red)
lexers.STYLE_SOON = fg(peach)
lexers.STYLE_TODAY = fg(green)
lexers.STYLE_TIME = fg(sky)
lexers.STYLE_SINCE = fg(overlay1)
lexers.STYLE_FILE = fg(overlay1)

-- Taskpaper, YAML, others the stock theme names
lexers.STYLE_TAG_DAY = fg(yellow)
lexers.STYLE_TAG_OVERDUE = fg(red)
lexers.STYLE_ERROR_INDENT = 'back:' .. red
lexers.STYLE_PROPERTY = lexers.STYLE_ATTRIBUTE
lexers.STYLE_COMMAND = lexers.STYLE_KEYWORD
lexers.STYLE_TARGET = ''
lexers.STYLE_SYMBOL = fg(pink)
lexers.STYLE_FILENAME = fg(subtext0)
lexers.STYLE_LINE = ''
lexers.STYLE_COLUMN = ''
lexers.STYLE_MESSAGE = ''
lexers.STYLE_KEYWORD_SOFT = fg(maroon)
