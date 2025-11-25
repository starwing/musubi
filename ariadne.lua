local utf8 = require "lua-utf8"
---@type fun(s: string, i?: integer, j?: integer): integer?
local utf8_len = utf8.len
---@type fun(s: string, n: integer, i?: integer): integer?, integer?
local utf8_offset = utf8.offset
---@type fun(s: string|integer, i?: integer, j?:integer, ambiwidth?: integer, fallback: integer?): integer
local utf8_width = utf8.width
---@type fun(s: string, width?: integer, i?: integer, j?:integer, ambiwidth?: integer, fallback: integer?): integer, integer, integer
local utf8_widthindex = utf8.widthindex
---@type fun(s: string, i?: integer, j?: integer, lax?: boolean): integer
local utf8_codepoint = utf8.codepoint

-- #region charset
--- @class (exact) CharSet
--- @field hbar        string
--- @field vbar        string
--- @field xbar        string
--- @field vbar_break  string
--- @field vbar_gap    string
--- @field uarrow      string
--- @field rarrow      string
--- @field ltop        string
--- @field mtop        string
--- @field rtop        string
--- @field lbot        string
--- @field mbot        string
--- @field rbot        string
--- @field lbox        string
--- @field rbox        string
--- @field lcross      string
--- @field rcross      string
--- @field underbar    string
--- @field underline   string
--- @field ellipsis    string

local characters = {
    ---@type CharSet
    unicode = {
        hbar = '─',
        vbar = '│',
        xbar = '┼',
        vbar_break = '┆',
        vbar_gap = '┆',
        uarrow = '▲',
        rarrow = '▶',
        ltop = '╭',
        mtop = '┬',
        rtop = '╮',
        lbot = '╰',
        mbot = '┴',
        rbot = '╯',
        lbox = '[',
        rbox = ']',
        lcross = '├',
        rcross = '┤',
        underbar = '┬',
        underline = '─',
        ellipsis = '…',
    },

    ---@type CharSet
    ascii = {
        hbar = '-',
        vbar = '|',
        xbar = '+',
        vbar_break = '*',
        vbar_gap = ':',
        uarrow = '^',
        rarrow = '>',
        ltop = ',',
        mtop = 'v',
        rtop = '.',
        lbot = '`',
        mbot = '^',
        rbot = '\'',
        lbox = '[',
        rbox = ']',
        lcross = '|',
        rcross = '|',
        underbar = '|',
        underline = '^',
        ellipsis = '...',
    },
}
-- #endregion

-- #region color
--- Color is a function that returns a rendered color string.  - It takes a
--- category. The category indicates what part of the report is being colored,
--- such as "kind", "margin", "note", etc.
--- "reset" is a special category that indicates resetting to default color.
--- @alias Color fun(category: ColorCategory): string?

--- @alias ColorCategory
--- | "reset"
--- | "error"
--- | "warning"
--- | "kind"
--- | "margin"
--- | "skipped_margin"
--- | "unimportant"
--- | "note"
--- | "label"

--- @class ColorGenerator
--- @field [integer] integer
--- @field min_brightness number

--- Creates a new ColorGenerator
--- @type fun(): ColorGenerator
local function cg_new()
    return { 30000, 15000, 35000, min_brightness = 0.5, }
end

--- returns the next color code
--- @type fun(self: ColorGenerator): Color
local function cg_next(self)
    for i = 1, #self do
        self[i] = self[i] + 40503 * ((i - 1) * 4 + 1130)
        self[i] = self[i] % 65536
    end
    local code = 16 + ((self[3] / 65535 * (1 - self.min_brightness)
            + self.min_brightness) * 5.0)
        + ((self[2] / 65535 * (1 - self.min_brightness)
            + self.min_brightness) * 30.0)
        + ((self[1] / 65535 * (1 - self.min_brightness)
            + self.min_brightness) * 180.0)
    return function(k)
        if k == "reset" then return "\x1b[0m" end
        return "\x1b[38;5;" .. math.floor(code) .. "m"
    end
end
-- #endregion

-- #region cache
--- @class (exact) Cache
--- @field fetch? fun(self: Cache, id: string): Source
--- @field [string] Source

---@type fun(): Cache
local function cache_new() return {} end

--- @type fun(self: Cache, id: string): Source?
local function cache_fetch(self, id)
    if self.fetch then return self:fetch(id) end
    return self[id]
end
-- #endregion

-- #region line
--- @class (exact) Line
--- @field offset       integer offset of this line in the original [`Source`]
--- @field len          integer character length of this line
--- @field byte_offset  integer byte offset of this line in the original [`Source`]
--- @field byte_len     integer byte length of this line in the original [`Source`]
--- @field newline      boolean whether this line ends with a newline

--- creates a new Line
--- @type fun(offset: integer, len: integer, byte_offset: integer,
---           byte_len: integer, newline: boolean): Line
local function line_new(offset, len, byte_offset, byte_len, newline)
    return {
        offset = offset,
        len = len,
        byte_offset = byte_offset,
        byte_len = byte_len,
        newline = newline,
    }
end

--- returns the span of this line in the original [`Source`]
--- @type fun(self: Line): integer, integer
local function line_span(l) return l.offset, l.offset + l.len - 1 end

--- checks if a position is within the span of this line
--- @type fun(self: Line, pos: integer): boolean
local function line_contains(l, pos)
    return pos >= l.offset and pos <= l.offset + l.len
end

--- returns the byte span of this line in the original [`Source`]
--- @type fun(self: Line): integer, integer
local function line_span_byte(l) return l.byte_offset, l.byte_offset + l.byte_len - 1 end

--- Returns the column number for a given offset
--- @type fun(self: Line, offset: integer): integer
local function line_col(l, offset) return offset - l.offset + 1 end

--- Check if an offset is within any of the multiline labels
--- @type fun(self: Line, multi_labels: LabelInfo[]): boolean
local function line_within_label(l, multi_labels)
    for _, info in ipairs(multi_labels) do
        if info.start_char < l.offset and info.end_char > l.offset then
            return true
        end
    end
    return false
end
-- #endregion

-- #region source
--- @class (exact) Source
--- @field id        string the source name
--- @field text      string the original source text
--- @field display_line_offset integer the line offset for display
--- @field fetch fun(self: Source, id: string): Source
--- @field [integer] Line

--- Splits the source code into lines
--- @type fun(code: string): Line[]
local function split_code(code)
    if #code == 0 then
        return { line_new(1, 0, 1, 0, false), }
    end
    local lines = {}
    local chars, bytes = 0, 0

    for ends in code:gmatch "()\n" do
        local chars_len = assert(utf8_len(code, bytes + 1, ends - 1))
        local bytes_len = ends - bytes - 1
        lines[#lines + 1] = line_new(chars + 1, chars_len, bytes + 1, bytes_len, true)
        chars = chars + chars_len + 1
        bytes = ends --[[@as integer]]
    end
    local chars_len = assert(utf8_len(code, bytes + 1, #code))
    local bytes_len = #code - bytes
    lines[#lines + 1] = line_new(chars + 1, chars_len, bytes + 1, bytes_len, false)
    return lines
end

--- creates a new Source
--- @type fun(code: string, name?: string, offset?: integer): Source
local function src_new(code, name, offset)
    local src = split_code(code) --[[@as Source]]
    src.text = code
    src.id = name or "<unknown>"
    src.display_line_offset = offset or 0
    src.fetch = function(self, _) return self end
    return src
end

--- binary_search locates the greatest line index whose key is <= target.
--- @type fun(lines: Line[], target: integer, key: string): integer
local function binary_search(lines, target, key)
    local l, u = 1, #lines
    while l <= u do
        local mid = l + (u - l + 1) // 2
        if lines[mid][key] <= target then
            l = mid + 1
        else
            u = mid - 1
        end
    end
    return l - 1
end

--- Returns the line contains the given offset
--- @type fun(self: Source, offset: integer): integer index
local function src_offset_line(self, offset)
    return binary_search(self, offset, "offset")
end

--- Returns the line contains the given byte offset
--- @type fun(self: Source, byte_offset: integer): integer index
local function src_byte_line(self, byte_offset)
    return binary_search(self, byte_offset, "byte_offset")
end

--- Get the line number shifted by display_line_offset
--- @type fun(self: Source, line_no: integer): integer
local function src_shifted_line_no(self, line_no)
    return line_no + self.display_line_offset
end

--- Find the character and repeat count that should be drawn
--- @type fun(self: Source, byte_offset: integer, col: integer, cfg: Config): integer, integer
local function src_char_width(self, byte_offset, col, cfg)
    local c = utf8_codepoint(self.text, utf8_offset(self.text, col, byte_offset))
    if c == 9 then -- tab
        return cfg.tab_width - ((col - 1) % cfg.tab_width), 32
    elseif c == 32 then
        return 1, 32
    else
        return utf8_width(c), c
    end
end
--- #endregion

-- #region config
--- @alias LabelAttach "start" | "end" | "middle"
--- @alias IndexType "byte" | "char"

--- @class (exact) Config
--- @field cross_gap        boolean show crossing gaps in cross arrows
--- @field label_attach     LabelAttach where to attach inline labels
--- @field compact          boolean whether to use compact mode
--- @field underlines       boolean whether to draw underlines for labels
--- @field multiline_arrows boolean whether to draw multiline arrows
--- @field color?           Color a color function or nil for no color
--- @field tab_width        integer number of spaces per tab
--- @field char_set         CharSet character set to use
--- @field index_type       IndexType index type for label positions
--- @field limit_width?      integer maximum line width for rendering

---@type Color
local function default_color(category)
    if category == "reset" then
        return "\x1b[0m"
    elseif category == "error" then
        return "\x1b[31m"       -- red
    elseif category == "warning" then
        return "\x1b[33m"       -- yellow
    elseif category == "kind" then
        return "\x1b[38;5;147m" -- fixed color
    elseif category == "margin" then
        return "\x1b[38;5;246m" -- fixed color
    elseif category == "skipped_margin" then
        return "\x1b[38;5;240m" -- fixed color
    elseif category == "unimportant" then
        return "\x1b[38;5;249m" -- fixed color
    elseif category == "note" then
        return "\x1b[38;5;115m" -- fixed color
    else
        return "\x1b[39m"       -- default
    end
end

--- @type Config
local cfg_default = {
    cross_gap = true,
    label_attach = "middle",
    compact = false,
    underlines = true,
    multiline_arrows = true,
    color = default_color,
    tab_width = 4,
    char_set = characters.unicode,
    index_type = "char",
    limit_width = nil, -- nil = no limit, positive integer = max width
}

--- Creates a new Config
--- @type fun(options?: table): Config
local function cfg_new(options)
    options = options or {}
    for k, v in pairs(cfg_default) do
        if options[k] == nil then
            options[k] = v
        end
    end
    return options --[[@as Config]]
end
-- #endregion

-- #region label
--- @class (exact) Label
--- @field start_pos  integer start position in the source
--- @field end_pos?   integer end position in the source, nil for single position
--- @field source_id? string source id this label belongs to
--- @field message?   string the message to display for this label
--- @field width      integer display width of the message
--- @field color?     Color the color for this label
--- @field order      integer order of this label in vertical sorting
--- @field priority   integer priority of this label when merging overlapping labels

--- Creates a new Label
--- @type fun(start_pos: integer, end_pos?: integer, source_id?: string): Label
local function label_new(start_pos, end_pos, source_id)
    return {
        start_pos = start_pos,
        end_pos = end_pos,
        source_id = source_id,
        message = nil,
        width = 0,
        color = nil,
        order = 0,
        priority = 0,
    }
end

--- Sets the message and width for this label
--- @type fun(self: Label, message: string, width?: integer): Label
local function label_set_message(self, message, width)
    self.message = message
    self.width = width or utf8_width(message or "")
    return self
end
-- #endregion

-- #region report
--- @class (exact) Report
--- @field kind string
--- @field code? string
--- @field message? string
--- @field notes string[]
--- @field helps string[]
--- @field pos integer
--- @field id? string
--- @field labels Label[]
--- @field config Config

--- creates a new Report
--- @type fun(kind: string, pos: integer, id?: string): Report
local function report_new(kind, pos, id)
    return {
        kind = kind,
        code = nil,
        message = nil,
        notes = {},
        helps = {},
        pos = pos,
        id = id,
        labels = {},
        config = cfg_default,
    }
end
-- #endregion

-- #region writer
---@class Writer
---@field private __name "Writer"
---@field private __index Writer
---@field config Config
---@field cur_color Color?
---@field cur_color_code string?
---@field line_no_width integer
---@field ellipsis_width integer
---@operator call(string): Writer
local Writer = {}
Writer.__name, Writer.__index = "Writer", Writer

--- creates a new Writer
--- @type fun(config: Config, line_no_width: integer): Writer
local function writer_new(config, line_no_width)
    return setmetatable({
        config = config,
        cur_color = nil,
        cur_color_code = nil,
        line_no_width = line_no_width,
        ellipsis_width = utf8.width(config.char_set.ellipsis),
    }, Writer)
end

--- Appends s to the writer
--- @type fun(self: Writer, s: any): Writer
function Writer:__call(s)
    self[#self + 1] = s
    return self
end

--- Sets the current color for the writer
--- @type fun(self: Writer, color?: Color): Writer
function Writer:use_color(color)
    color = color or self.config.color
    if self.cur_color_code and color ~= self.cur_color then
        self:reset()
    end
    self.cur_color = color
    return self
end

--- Generates color functions for each category
--- @type fun(category: ColorCategory): fun(self: Writer, s: any): Writer
local function gen_color_func(category)
    return function(self, s)
        local color = self.cur_color or self.config.color
        if color then
            local color_code = color(category)
            if self.cur_color_code and self.cur_color_code ~= color_code then
                self[#self + 1] = color "reset"
            end
            if not self.cur_color_code or self.cur_color_code ~= color_code then
                self[#self + 1] = color_code
            end
            self.cur_color = color
            self.cur_color_code = color_code
        end
        self[#self + 1] = s
        return self
    end
end

Writer.error = gen_color_func "error"
Writer.warning = gen_color_func "warning"
Writer.kind = gen_color_func "kind"
Writer.margin = gen_color_func "margin"
Writer.skipped_margin = gen_color_func "skipped_margin"
Writer.unimportant = gen_color_func "unimportant"
Writer.note = gen_color_func "note"
Writer.label = gen_color_func "label"

--- Resets the current color and appends s to the writer
--- @type fun(self: Writer, s: any): Writer
function Writer:reset(s)
    local color = self.cur_color or self.config.color
    if color then
        if self.cur_color_code then
            self[#self + 1] = color "reset"
        end
        self.cur_color = nil
        self.cur_color_code = nil
    end
    self[#self + 1] = s
    return self
end

--- Adds padding to the writer
--- @type fun(self: Writer, count: integer, s?: any): Writer
function Writer:padding(count, s)
    if count > 0 then
        self[#self + 1] = (s or ' '):rep(count)
    end
    return self
end

--- Write s when not in compact mode
--- @type fun(self: Writer, s: any): Writer
function Writer:compact(s)
    if not self.config.compact then
        self[#self + 1] = s
    end
    return self
end

--- Writes a label if cur_color is set, otherwise writes an unimportant message
--- @type fun(self: Writer, cur_color: Color?, s: any): Writer
function Writer:label_or_unimportant(cur_color, s)
    if cur_color then
        return self:use_color(cur_color):label(s)
    end
    return self:unimportant(s)
end

--- Return the final string
--- @type fun(self: Writer): string
function Writer:tostring() return table.concat(self) end

-- #endregion

-- region label_info
---@class (exact) LabelInfo
---@field multi boolean whether this label spans multiple lines
---@field start_char integer the start character position of this label
---@field end_char? integer the end character position of this label
---@field label Label the original label

--- creates a new LabelInfo
--- @type fun(label: Label, src: Source, index_type: "byte" | "char"): LabelInfo
local function info_new(label, src, index_type)
    -- find label line and character positions
    local given_start, given_end = label.start_pos, label.end_pos
    ---@type integer, integer?, Line, Line
    local label_start_char, label_end_char, start_line, end_line
    if index_type == "char" then
        start_line = assert(src[src_offset_line(src, given_start)],
            "label start position out of range")
        label_start_char = given_start
        if given_end and given_start <= given_end then
            end_line = assert(src[src_offset_line(src, given_end)])
            label_end_char = given_end
        else
            end_line = start_line
        end
    else
        local line_no = src_byte_line(src, given_start)
        start_line = assert(src[line_no], "start byte offset out of range")
        label_start_char = start_line.offset +
            assert(utf8_len(src.text, start_line.byte_offset, given_start - 1))
        if given_end and given_start <= given_end then
            line_no = src_byte_line(src, given_end)
            end_line = assert(src[line_no], "end byte offset out of range")
            label_end_char = end_line.offset +
                assert(utf8_len(src.text, end_line.byte_offset, given_end)) - 1
        else
            end_line = start_line
        end
    end
    if label_start_char > start_line.offset + start_line.len then
        label_start_char = start_line.offset + start_line.len
        label_end_char = nil
    end
    return {
        multi = start_line ~= end_line,
        start_char = label_start_char,
        end_char = label_end_char,
        label = label,
    }
end
-- #endregion

-- #region label_cluster
--- @class (exact) LineLabel
--- @field col integer the column number in the line
--- @field info LabelInfo the label info
--- @field draw_msg boolean whether to draw the message in this line

---@class (exact) LabelCluster
---@field line Line the line this cluster represents
---@field line_no integer the line number in the source
---@field margin_label LineLabel? the margin label for this line
---@field line_labels LineLabel[] the labels in this line
---@field arrow_len integer the length of the arrows line
---@field min_col integer the first column of labels in this line
---@field max_msg_width integer the maximum message width in this line
---@field start_col? integer the start column for rendering
---@field end_col? integer the end column for rendering

--- Length of margin area
--- @type fun(group: Group, cfg: Config): integer
local function margin_len(group, cfg)
    local len = #group.multi_labels
    return (len > 0 and len + 1 or 0) * (cfg.compact and 2 or 1)
end

--- Collect multiline labels for a specific line
--- @type fun(line_labels: LineLabel[], line: Line, multi_labels: LabelInfo[])
local function collect_multi_labels(line_labels, line, multi_labels)
    for _, info in ipairs(multi_labels) do
        local ll --[[@as LineLabel?]]
        if line_contains(line, info.start_char) then
            ll = { col = line_col(line, info.start_char), draw_msg = false }
        elseif info.end_char and line_contains(line, info.end_char) then
            ll = { col = line_col(line, info.end_char), draw_msg = true }
        end
        if ll then
            ll.info = info
            line_labels[#line_labels + 1] = ll
        end
    end
end

--- Collect inline labels for a specific line
--- @type fun(line_labels: LineLabel[], line: Line, labels: LabelInfo[], label_attach: LabelAttach)
local function collect_inline_labels(line_labels, line, labels, label_attach)
    local start_char, end_char = line_span(line)
    for _, info in ipairs(labels) do
        if info.start_char >= start_char and
            (info.end_char or info.start_char) <= end_char + 1
        then
            local col = info.start_char
            if label_attach == "end" then
                col = info.end_char or info.start_char
            elseif label_attach == "middle" and info.end_char then
                col = (info.start_char + info.end_char + 1) // 2
            end
            line_labels[#line_labels + 1] = {
                col = line_col(line, col),
                info = info,
                draw_msg = true,
            }
        end
    end
end

--- Sort line labels by order, column and desc start position
--- @type fun(line_labels: LineLabel[])
local function sort_line_labels(line_labels)
    table.sort(line_labels, function(a, b)
        if a.info.label.order ~= b.info.label.order then
            return a.info.label.order < b.info.label.order
        elseif a.col ~= b.col then
            return a.col < b.col
        end
        return a.info.start_char > b.info.start_char
    end)
end

--- Creates a empty LabelCluster
--- @type fun(line: Line, line_no: integer): LabelCluster
local function lc_new(line, line_no)
    return {
        line = line,
        line_no = line_no,
        margin_label = nil,
        line_labels = {},
        arrow_len = 0,
        min_col = 0,
        max_msg_width = 0,
        start_col = 1,
        end_col = nil,
    }
end

--- @type fun(line: Line, line_no: integer, group: Group,
---           line_no_width: integer, cfg: Config): LabelCluster[]
local function lc_assemble_clusters(line, line_no, group, line_no_width, cfg)
    --- @type LineLabel[]
    local line_labels = {}
    collect_multi_labels(line_labels, line, group.multi_labels)
    collect_inline_labels(line_labels, line, group.labels, cfg.label_attach)
    if #line_labels == 0 then return {} end
    sort_line_labels(line_labels)

    local lc              = lc_new(line, line_no)
    lc.min_col            = nil

    local clusters        = { lc } --[=[@as LabelCluster[]]=]
    local min_start_width, max_end_width
    local extra_arrow_len = cfg.compact and 1 or 2
    local limit_width     = cfg.limit_width and
        cfg.limit_width - line_no_width - 4 - margin_len(group, cfg) or nil
    for _, ll in ipairs(line_labels) do
        local end_col = ll.info.multi and ll.col or
            line_col(line, ll.info.end_char or ll.info.start_char - 1)
        if limit_width then
            -- TODO: O(n^2) need optimize
            local start_col = ll.info.multi and ll.col or
                line_col(line, ll.info.start_char)
            local start_width = utf8_width(group.src.text, line.byte_offset,
                utf8_offset(group.src.text, start_col, line.byte_offset) - 1)
            local _, cur_end_byte = utf8_offset(group.src.text,
                end_col, line.byte_offset)
            local end_width = utf8_width(group.src.text, line.byte_offset,
                cur_end_byte)
            min_start_width = math.min(min_start_width or start_width, start_width)
            max_end_width = math.max(max_end_width or end_width, end_width)
            local cur_width = (max_end_width - min_start_width) +
                (ll.draw_msg and ll.info.label.message and
                    extra_arrow_len + 1 + ll.info.label.width or 0)
            if (#lc.line_labels > 0 or lc.margin_label) and cur_width > limit_width then
                min_start_width, max_end_width = nil, nil
                lc = lc_new(line, line_no)
                lc.min_col = nil
                clusters[#clusters + 1] = lc
            end
        end
        if ll.info.multi then
            if not lc.margin_label then lc.margin_label = ll end
            if (not cfg.limit_width or lc.margin_label ~= ll) and ll.draw_msg then
                end_col = lc.line.len + (line.newline and 1 or 0)
            end
        end
        if lc.margin_label ~= ll or (ll.draw_msg and ll.info.label.message) then
            lc.line_labels[#lc.line_labels + 1] = ll
        end
        lc.arrow_len = math.max(lc.arrow_len, end_col + extra_arrow_len)
        local min_col = ll.info.multi and ll.col or
            line_col(line, ll.info.start_char)
        lc.min_col = math.min(lc.min_col or min_col, min_col)
        lc.max_msg_width = math.max(lc.max_msg_width, ll.info.label.width)
    end
    return clusters
end

--- Calculate the start position for rendering a line
--- @type fun(lc: LabelCluster, group: Group,
---           line_no_width: integer, ellipsis_width: integer, cfg: Config)
local function lc_calc_col_range(lc, group, line_no_width, ellipsis_width, cfg)
    if not cfg.limit_width then return end
    local line, arrow_len, min_col, max_msg_width =
        lc.line, lc.arrow_len, lc.min_col, lc.max_msg_width
    local src = group.src

    local margin_count = margin_len(group, cfg)
    local fix_width = line_no_width + 4 +       -- line no and margin
        margin_count * (cfg.compact and 1 or 2) -- margin arrows
    local limited = cfg.limit_width - fix_width

    -- the width of arrows line:
    --                          |<-- min_width ->|
    --  1 | ...aaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbb...
    --    |                     ^^|^^
    --    |                       `---- found here
    --                          ^ min_col  ...-->| arrow_limit
    --                                ^ arrow_len (arrow_width)
    -- line.len may be less than arrow_len
    local extra = math.max(0, arrow_len - line.len)
    local _, line_part = utf8_offset(src.text, arrow_len, line.byte_offset)
    local _, line_end = line_span_byte(line)
    if not line_part then line_part = line_end end
    local arrow = utf8_width(src.text, line.byte_offset, line_part) + extra
    local edge = arrow + 1 + max_msg_width -- 1: space before msg

    -- all line fits in limit_width? No need to skip
    local line_width = utf8_width(src.text, line.byte_offset, line_end)
    if edge <= limited and line_width <= limited then return end

    -- min_col already overflow? Using min_col
    local essential = utf8_width(src.text,
            assert(utf8_offset(src.text, min_col, line.byte_offset)), line_part) +
        1 + max_msg_width
    if essential + ellipsis_width >= limited then
        lc.start_col = min_col
        lc.end_col = math.min(line.len, arrow_len + (utf8_widthindex(src.text,
            1 + max_msg_width - ellipsis_width,
            line_part + 1, line_end)))
        return
    end

    local skip = edge - limited + ellipsis_width + 1
    if skip <= 0 then
        lc.start_col, lc.end_col = 1, math.min(line.len,
            arrow_len + (utf8_widthindex(src.text,
                limited - arrow - ellipsis_width,
                line_part + 1, line_end)))
        return
    end
    local balance = 0
    if line_width > edge then
        local avail = line_width - edge
        local desired = (limited - essential) // 2
        balance = desired + math.max(0, desired - avail)
    end
    lc.start_col = (utf8_widthindex(src.text, skip + balance,
        line.byte_offset, line_part))
    local end_col, idx, chwidth = utf8_widthindex(src.text,
        1 + max_msg_width + balance - ellipsis_width,
        line_part + 1, line_end)
    -- multi width in the end_col edge?
    if idx ~= chwidth then end_col = end_col - 1 end
    lc.end_col = math.min(line.len, arrow_len + end_col)
end

--- Get the highest priority highlight for a column
--- @type fun(lc: LabelCluster, col: integer, group: Group): LabelInfo?
local function lc_get_highlight(lc, col, group)
    local result
    local offset = lc.line.offset + col - 1

    local function update_result(info)
        if offset < info.start_char or offset > info.end_char then return end
        if not result then
            result = info
        end
        if info.label.priority > result.label.priority then
            result = info
        elseif info.label.priority == result.label.priority then
            local info_len = info.end_char - info.start_char + 1
            local result_len = result.end_char - result.start_char + 1
            if info_len < result_len then
                result = info
            end
        end
    end

    if lc.margin_label then
        update_result(lc.margin_label.info)
    end
    for _, info in ipairs(group.multi_labels) do
        update_result(info)
    end
    for _, ll in ipairs(lc.line_labels) do
        if ll.info.end_char then
            update_result(ll.info)
        end
    end
    return result
end

--- Should we draw a vertical bar as part of a label arrow on this line?
--- @type fun(lc: LabelCluster, col: integer, row: integer): LineLabel?
local function lc_get_vbar(lc, col, row)
    for i, ll in ipairs(lc.line_labels) do
        if (ll.info.label.message or ll.info.multi) and
            lc.margin_label ~= ll and ll.col == col and row <= i
        then
            return ll
        end
    end
end

--- Should we draw an underline as part of a label arrow on this line?
--- @type fun(lc: LabelCluster, col: integer, cfg: Config): LineLabel?
local function lc_get_underline(lc, col, cfg)
    if not cfg.underlines then
        return nil
    end
    local offset = lc.line.offset + col - 1
    ---@type LineLabel?
    local result
    for i, ll in ipairs(lc.line_labels) do
        if not ll.info.multi and
            ll.info.start_char <= offset and
            (ll.info.end_char and offset <= ll.info.end_char)
        then
            if not result then
                result = ll
            elseif ll.info.label.priority > result.info.label.priority then
                result = ll
            elseif ll.info.label.priority == result.info.label.priority then
                local ll_len = ll.info.end_char - ll.info.start_char + 1
                local res_len = result.info.end_char - result.info.start_char + 1
                if ll_len < res_len then
                    result = ll
                end
            end
        end
    end
    return result
end

--- Render a line with highlights
--- @type fun(W: Writer, lc: LabelCluster, group: Group, cfg: Config)
function Writer.render_line(W, lc, group, cfg)
    local line = lc.line
    local src = group.src

    --- @type Color?
    local cur_color
    local cur_offset = lc.start_col
    local cur_offset_byte = assert(utf8_offset(src.text,
        lc.start_col, line.byte_offset))
    for i = lc.start_col, lc.end_col or line.len do
        local highlight = lc_get_highlight(lc, i, group)
        local next_color = highlight and highlight.label.color
        local repeat_count, cp = src_char_width(src, line.byte_offset, i, cfg)
        if cur_color ~= next_color or (cp == 32 and repeat_count > 1) then
            local next_start_bytes = assert(utf8_offset(src.text,
                i - cur_offset + 1, cur_offset_byte))
            if i > cur_offset then
                W:label_or_unimportant(cur_color, (src.text:sub(
                    cur_offset_byte, next_start_bytes - 1
                ):gsub("\t", ""))):reset()
            end
            if cp == 32 and repeat_count > 1 then
                W:label_or_unimportant(next_color, (" "):rep(repeat_count))
            end
            cur_color = next_color
            cur_offset = i
            cur_offset_byte = next_start_bytes
        end
    end
    local _, end_bytes = line_span_byte(line)
    if lc.end_col and lc.end_col < line.len then
        end_bytes = assert(utf8_offset(src.text, lc.end_col + 1, line.byte_offset)) - 1
    end
    W:label_or_unimportant(cur_color, (src.text:sub(
        cur_offset_byte, end_bytes
    ):gsub("\t", ""))):reset()
end

--- Render arrows for a line
--- @type fun(W: Writer, lc: LabelCluster, group: Group)
function Writer.render_arrows(W, lc, group)
    local cfg = W.config
    local draw = cfg.char_set
    local src = group.src

    -- Arrows
    local first = true
    for row, ll in ipairs(lc.line_labels) do
        -- No message to draw thus no arrow to draw
        if ll.info.label.message or (ll.info.multi and lc.margin_label ~= ll) then
            if not W.config.compact then
                -- Margin alternate
                W:render_lineno(nil, false)
                W:render_margin(lc, group, ll, "none")
                if lc.start_col > 1 then W:padding(W.ellipsis_width) end
                for col = lc.start_col, lc.arrow_len do
                    local width = 1
                    if col <= lc.line.len then
                        width = src_char_width(src, lc.line.byte_offset, col, cfg)
                    end
                    local vbar = lc_get_vbar(lc, col, row)
                    local underline
                    if first then
                        underline = lc_get_underline(lc, col, cfg)
                    end
                    if vbar and underline then
                        local a = draw.underbar
                        W:use_color(vbar.info.label.color):label(a)
                        W:padding(width - 1, draw.underline)
                    elseif vbar then
                        local a = draw.vbar
                        if vbar.info.multi and first and cfg.multiline_arrows then
                            a = draw.uarrow
                        end
                        W:use_color(vbar.info.label.color):label(a):reset()
                        W:padding(width - 1)
                    elseif underline then
                        W:use_color(underline.info.label.color)
                        W:label():padding(width, draw.underline)
                    else
                        W:reset():padding(width)
                    end
                end
                W:reset "\n"
            end

            -- Margin
            W:render_lineno(nil, false)
            W:render_margin(lc, group, ll, "arrow")

            -- Lines
            if lc.start_col > 1 then
                local a = " "
                if ll == lc.margin_label or not ll.draw_msg then
                    a = draw.hbar
                end
                W:padding(W.ellipsis_width, a)
            end
            for col = lc.start_col, lc.arrow_len do
                local width = 1
                if col <= lc.line.len then
                    width = src_char_width(src, lc.line.byte_offset, col, cfg)
                end
                local is_hbar = (col > ll.col) ~= ll.info.multi or
                    ll.draw_msg and ll.info.label.message and col > ll.col
                local vbar = lc_get_vbar(lc, col, row)
                if col == ll.col and lc.margin_label ~= ll then
                    local a = draw.rbot
                    if not ll.info.multi then
                        a = draw.lbot
                    elseif ll.draw_msg then
                        a = ll.info.label.message and draw.mbot or draw.rbot
                    end
                    W:use_color(ll.info.label.color):label(a):padding(width - 1, draw.hbar)
                elseif vbar and col ~= ll.col then
                    local a, b = draw.vbar, ' '
                    if is_hbar then
                        a = draw.xbar
                        if cfg.cross_gap then
                            a, b = draw.hbar, draw.hbar
                        end
                    elseif vbar.info.multi and first and cfg.compact then
                        a = draw.uarrow
                    end
                    W:use_color(vbar.info.label.color):label(a):padding(width - 1, b)
                elseif is_hbar then
                    W:use_color(ll.info.label.color):label():padding(width, draw.hbar)
                else
                    W:reset():padding(width)
                end
            end
            first = false
            W:reset()
            if ll.draw_msg then
                W " " (ll.info.label.message)
            end
            W "\n"
        end
    end
end

--- Render a label cluster
--- @type fun(W: Writer, lc: LabelCluster, group: Group)
function Writer.render_label_cluster(W, lc, group)
    -- Determine label bounds so we know where to put error messages
    local cfg = W.config
    local draw = cfg.char_set

    W:render_lineno(lc.line_no, false)
    W:render_margin(lc, group, nil, "line")
    if lc.start_col > 1 then
        W:unimportant(draw.ellipsis):reset()
    end
    W:render_line(lc, group, cfg)
    if lc.end_col and lc.end_col < lc.line.len then
        W:unimportant(draw.ellipsis):reset()
    end
    W "\n"
    W:render_arrows(lc, group)
end

-- #endregion

-- #region source_group

local MIN_FILENAME_WIDTH = 8

---@class (exact) Group
---@field src Source
---@field start_char integer
---@field end_char? integer
---@field labels LabelInfo[]
---@field multi_labels LabelInfo[]

--- creates a new SourceGroup
--- @type fun(src: Source, info: LabelInfo): Group
local function sg_new(src, info)
    return {
        src = src,
        start_char = info.start_char,
        end_char = info.end_char,
        labels = { not info.multi and info or nil },
        multi_labels = { info.multi and info or nil }
    }
end

--- Add label information to the source group
--- @type fun(group: Group, info: LabelInfo)
local function sg_add_label_info(group, info)
    group.start_char = math.min(group.start_char, info.start_char)
    if info.end_char and (not group.end_char
            or info.end_char > group.end_char) then
        group.end_char = info.end_char
    end
    if info.multi then
        group.multi_labels[#group.multi_labels + 1] = info
    else
        group.labels[#group.labels + 1] = info
    end
end

--- Get the last line number of the source group
--- @type fun(group: Group): integer
local function sg_last_line_no(group)
    local src = group.src
    return src_shifted_line_no(src,
        src_offset_line(src, group.end_char or group.start_char))
end

--- Calculate the line and column string for a report position
--- @type fun(group: Group, ctx_id: string?, ctx_pos: integer, cfg: Config): string
local function sg_calc_location(group, ctx_id, ctx_pos, cfg)
    local src = group.src
    ---@type Line?, integer?, integer?
    local line, line_no, col_no
    if not ctx_id or src.id == ctx_id then
        if cfg.index_type == "byte" then
            line_no = src_byte_line(src, ctx_pos)
            line = assert(src[line_no], "byte offset out of range")
            local _, line_byte_end = line_span_byte(line)
            if line and ctx_pos <= line_byte_end then
                col_no = assert(utf8_len(src.text, line.byte_offset, ctx_pos - 1)) + 1
            else
                line_no = nil
            end
        else
            line_no = src_offset_line(src, ctx_pos)
            line = src[line_no]
            if line then
                col_no = line_col(line, ctx_pos)
            end
        end
    else
        local start = (group.labels[1] or group.multi_labels[1]).start_char
        line_no = src_offset_line(src, start)
        line = src[line_no]
        if line then
            col_no = line_col(line, start)
        end
    end
    if not line_no then return "?:?" end
    return ("%d:%d"):format(src_shifted_line_no(src, line_no), col_no)
end

--- Render the reference line for a source group
--- @type fun(W: Writer, idx: integer, group: Group, report_id: string?, report_pos: integer)
function Writer.render_reference(W, idx, group, report_id, report_pos)
    local cfg = W.config
    local draw = cfg.char_set
    local id = group.src.id:gsub("\t", " ")
    local loc = sg_calc_location(group, report_id, report_pos, cfg)
    if cfg.limit_width then
        local id_width = utf8.width(id)
        -- assume draw's components' width are all 1
        local fixed_width = utf8.width(loc) + W.line_no_width + 9
        if id_width + fixed_width > cfg.limit_width then
            local avail = cfg.limit_width - fixed_width - W.ellipsis_width
            if avail < MIN_FILENAME_WIDTH then
                avail = MIN_FILENAME_WIDTH
            end
            id = draw.ellipsis .. id:sub((utf8.widthlimit(id, -avail)))
        end
    end
    W:padding(W.line_no_width + 2)
    W:margin(idx == 1 and draw.ltop or draw.vbar)
    W(draw.hbar)(draw.lbox):reset " "
    W(id) ":" (loc) " ":margin(draw.rbox):reset "\n"
end

--- Render the margin arrows for a specific line
--- @type fun(W: Writer, lc: LabelCluster, group: Group,
---           report_row?: LineLabel, type: "line"|"arrow"|"ellipsis"|"none")
function Writer.render_margin(W, lc, group,
                              report, type)
    if #group.multi_labels == 0 then return end
    local draw = W.config.char_set
    local start_char = lc.line.offset + (lc.start_col or 1) - 1
    local end_char = lc.line.offset + (lc.end_col or lc.line.len) -- without -1

    ---@type LabelInfo?, LabelInfo?
    local hbar, ptr
    local ptr_is_start = false

    for _, info in ipairs(group.multi_labels) do
        ---@type LabelInfo?, LabelInfo?
        local vbar, corner
        local is_start = info.start_char >= start_char and info.start_char <= end_char
        if info.end_char >= start_char and info.start_char <= end_char then
            local is_margin = lc.margin_label and lc.margin_label.info == info
            local is_end = info.end_char >= start_char and info.end_char <= end_char
            if is_margin and type == "line" then
                ptr, ptr_is_start = info, is_start
            elseif not is_start and (not is_end or type == "line") then
                vbar = info
            elseif report and report.info == info then
                if type ~= "arrow" and not is_start then
                    vbar = info
                elseif is_margin then
                    vbar = assert(lc.margin_label).info
                end
                if type == "arrow" and not (is_margin and is_start) then
                    hbar, corner = info, info
                end
            elseif report then
                local info_is_below
                if not is_margin then
                    for j, ll in ipairs(assert(lc.line_labels)) do
                        if ll.info == info then break end
                        if ll == report then
                            info_is_below = true
                            break
                        end
                    end
                end
                if is_start or not is_margin or info.label.message then
                    -- if info is_start,
                    --     hbar required to connect below only *after* info line
                    -- otherwise, connect above *before* info line
                    if is_start and not info_is_below then
                        vbar = info
                    elseif not is_start and info_is_below then
                        vbar = info
                    end
                end
            end
        end

        if ptr and type == "line" and info ~= ptr then
            hbar = hbar or ptr
        end

        if corner then
            local a = is_start and draw.ltop or draw.lbot
            W:use_color(corner.label.color):label(a):compact(draw.hbar)
        elseif vbar and hbar and not W.config.cross_gap then
            W:use_color(vbar.label.color):label(draw.xbar):compact(draw.hbar)
        elseif hbar then
            W:use_color(hbar.label.color):label(draw.hbar):compact(draw.hbar)
        elseif vbar then
            local a = type == "ellipsis" and draw.vbar_gap or draw.vbar
            W:use_color(vbar.label.color):label(a):compact ' '
        elseif ptr and type == "line" then
            local a, b = draw.hbar, draw.hbar
            if info == ptr then
                if ptr_is_start then
                    a = draw.ltop
                elseif not info.label.message then
                    a = draw.lbot
                else
                    a = draw.lcross
                end
            end
            W:use_color(ptr.label.color):label(a):compact(b)
        else
            W:reset(W.config.compact and ' ' or '  ')
        end
    end
    if hbar and (not type == "line" or hbar ~= ptr) then
        W:use_color(hbar.label.color):label(draw.hbar):compact(draw.hbar):reset()
    elseif ptr and type == "line" then
        W:use_color(ptr.label.color):label(draw.rarrow):compact ' ':reset()
    else
        W:reset(W.config.compact and ' ' or '  ')
    end
end

--- Render the lines for a source group
--- @type fun(W: Writer, group: Group)
function Writer.render_lines(W, group)
    local src = group.src
    local cfg = W.config
    local is_ellipsis = false
    local line_start = src_offset_line(src, group.start_char)
    local line_end = line_start
    if group.end_char then
        line_end = src_offset_line(src, group.end_char)
    end
    for idx = line_start, line_end do
        local line_no = src_shifted_line_no(src, idx)
        local line = assert(src[idx], "group line out of range")
        local clusters = lc_assemble_clusters(line, line_no, group,
            W.line_no_width, cfg)
        if #clusters > 0 then
            for _, cluster in ipairs(clusters) do
                lc_calc_col_range(cluster, group, W.line_no_width, W.ellipsis_width, cfg)
                W:render_label_cluster(cluster, group)
            end
        elseif not is_ellipsis and line_within_label(line, group.multi_labels) then
            W:render_lineno(nil, true)
            --- @diagnostic disable-next-line missing-fields
            W:render_margin({ line = line }, group, nil, "ellipsis")
            W "\n"
        elseif not is_ellipsis and not W.config.compact then
            -- Skip this line if we don't have labels for it
            W:render_lineno(nil, false)
            W "\n"
        end
        is_ellipsis = #clusters == 0
    end
end

-- #endregion

-- #region render

--- Calculate the maximum width of line numbers in all source groups
--- @type fun(groups: Group[]): integer
local function calc_line_no_width(groups)
    local width = 0
    for _, group in ipairs(groups) do
        local line_no = sg_last_line_no(group)
        if line_no then
            local cur_width, max_line_no = 1, 1
            while max_line_no * 10 <= line_no do
                cur_width, max_line_no = cur_width + 1, max_line_no * 10
            end
            if width < cur_width then
                width = cur_width
            end
        end
    end
    return width
end

--- creates a new RenderContext
--- @type fun(id: string, cache: Cache, labels: Label[], cfg: Config): Writer, Group[]
local function context_new(id, cache, labels, cfg)
    -- group labels by source
    ---@type Group[]
    local groups = {}
    for _, label in ipairs(labels) do
        local src = assert(cache_fetch(cache, label.source_id), "source not found")
        local info = info_new(label, src, cfg.index_type)
        local key = label.source_id or id or "<unknown>"
        local group = groups[key]
        if group then
            sg_add_label_info(group, info)
        else
            group = sg_new(src, info)
            groups[#groups + 1] = group
            groups[key] = group
        end
    end
    for _, group in ipairs(groups) do
        -- Sort labels by length
        table.sort(group.multi_labels, function(a, b)
            local alen = a.end_char - a.start_char + 1
            local blen = b.end_char - b.start_char + 1
            return alen > blen
        end)
    end
    -- line number maximum width
    local line_no_width = calc_line_no_width(groups)
    return writer_new(cfg, line_no_width), groups
end

--- Render the header for a report
--- @type fun(W: Writer, kind: string, code: string|nil, message: string)
function Writer.render_header(W, kind, code, message)
    local lkind = kind:lower()
    if lkind == "error" then
        W:error()
    elseif lkind == "warning" then
        W:warning()
    else
        W:kind()
    end
    if code then
        W "[" (code) "] "
    end
    W(kind) ":":reset " " (message) "\n"
end

--- Render the line number for a specific line
--- @type fun(W: Writer, line_no: integer|nil, is_ellipsis: boolean)
function Writer.render_lineno(W, line_no, is_ellipsis)
    local draw = W.config.char_set
    if line_no and not is_ellipsis then
        local line_no_str = tostring(line_no)
        W " ":padding(W.line_no_width - #line_no_str)
        W:margin(line_no_str) " " (draw.vbar):reset()
    else
        W " ":padding(W.line_no_width + 1)
        if is_ellipsis then
            W:skipped_margin(draw.vbar_gap)
        else
            W:skipped_margin(draw.vbar)
        end
    end
    if not W.config.compact then
        W " "
    end
end

--- Render notes or help items
--- @type fun(W: Writer, prefix: string, items: string[])
function Writer.render_help_or_note(W, prefix, items)
    for i, item in ipairs(items) do
        if not W.config.compact then
            W:render_lineno(nil, false)
            W "\n"
        end
        local item_prefix = #items > 1 and ("%s %d"):format(prefix, i) or prefix
        local item_prefix_len
        for line in item:gmatch "([^\n]*)\n?" do
            W:render_lineno(nil, false)
            if not item_prefix_len then
                W:note(item_prefix) ": " (line) "\n"
                item_prefix_len = #item_prefix + 2
            else
                W:padding(item_prefix_len)(line) "\n"
            end
        end
    end
end

--- Render the footer for a report
--- @type fun(W: Writer, group_count: integer, helps: string[], notes: string[])
function Writer.render_footer(W, group_count, helps, notes)
    W:render_help_or_note("Help", helps)
    W:render_help_or_note("Note", notes)
    if group_count > 0 and not W.config.compact then
        local draw = W.config.char_set
        W:margin():padding(W.line_no_width + 2, draw.hbar)(draw.rbot)
            :reset "\n"
    end
end

--- Writes an empty line
--- @type fun(self: Writer)
function Writer.render_empty_line(W)
    local cfg = W.config
    local draw = cfg.char_set
    if not cfg.compact then
        W:padding(W.line_no_width + 2):margin(draw.vbar):reset "\n"
    end
end

--- render the report
--- @type fun(report: Report, cache: Cache): string
local function render(report, cache)
    local cfg = report.config
    local W, groups = context_new(report.id, cache, report.labels, cfg)
    W:render_header(report.kind, report.code, report.message)
    for idx, group in ipairs(groups) do
        W:render_reference(idx, group, report.id, report.pos)
        W:render_empty_line()
        W:render_lines(group)
        if idx ~= #groups then
            W:render_empty_line()
        end
    end
    W:render_footer(#groups, report.helps, report.notes)
    return W:tostring()
end
-- #endregion

-- #region API

--- @generic T
--- @param name string
--- @param t? T
--- @return T
local function meta(name, t)
    t = t or {}
    t.__name = name
    t.__index = t
    return t
end

--- @class CacheAPI : Cache
local Cache = meta "Cache"
--- @class SourceAPI : Source, Cache
local Source = meta "Source"
--- @class LabelAPI : Label
local Label = meta "Label"
--- @class ColorGeneratorAPI : ColorGenerator
local ColorGenerator = meta "ColorGenerator"
--- @class ConfigAPI : Config
local Config = meta "Config"
--- @class ReportAPI : Report
local Report = meta "Report"

--- @type fun(): CacheAPI
function Cache.new()
    --- @type CacheAPI
    return setmetatable(cache_new(), Cache)
end

--- @type fun(content: string, id?: string, offset?: integer): SourceAPI
function Source.new(content, id, offset)
    --- @type SourceAPI
    return setmetatable(src_new(content, id, offset), Source)
end

--- @type fun(self: SourceAPI, line: Line): string
function Source:get_line(line)
    return string.sub(self.text --[[@as string]], line_span_byte(line))
end

--- @type fun(): ColorGeneratorAPI
function ColorGenerator.new()
    --- @type ColorGeneratorAPI
    return setmetatable(cg_new(), ColorGenerator)
end

--- @type fun(self: ColorGeneratorAPI): Color
function ColorGenerator:next() return cg_next(self) end

--- @type fun(opts: table): ConfigAPI
function Config.new(opts)
    --- @type ConfigAPI
    return setmetatable(cfg_new(opts), Config)
end

--- @type fun(start_pos: integer, end_pos: integer|nil, id: string|nil): LabelAPI
function Label.new(start_pos, end_pos, id)
    --- @type LabelAPI
    return setmetatable(label_new(start_pos, end_pos, id), Label)
end

--- @type fun(self: LabelAPI, message: string, width?: integer): LabelAPI
function Label:with_message(message, width)
    label_set_message(self, message, width)
    return self
end

--- @type fun(self: LabelAPI, order: integer): LabelAPI
function Label:with_order(order)
    self.order = order
    return self
end

--- @type fun(self: LabelAPI, priority: integer): LabelAPI
function Label:with_priority(priority)
    self.priority = priority
    return self
end

--- @type fun(self: LabelAPI, color: Color): LabelAPI
function Label:with_color(color)
    self.color = color
    return self
end

--- @type fun(kind: string, pos?: integer, id?: string): ReportAPI
function Report.build(kind, pos, id)
    --- @type ReportAPI
    return setmetatable(report_new(kind, pos, id), Report)
end

--- @type fun(self: ReportAPI, label: Label): ReportAPI
function Report:with_label(label)
    self.labels[#self.labels + 1] = label
    return self
end

--- @type fun(self: ReportAPI, note: string): ReportAPI
function Report:with_note(note)
    self.notes[#self.notes + 1] = note
    return self
end

--- @type fun(self: ReportAPI, help: string): ReportAPI
function Report:with_help(help)
    self.helps[#self.helps + 1] = help
    return self
end

--- @type fun(self: ReportAPI, config: Config): ReportAPI
function Report:with_config(config)
    self.config = config
    return self
end

--- @type fun(self: ReportAPI, code: string): ReportAPI
function Report:with_code(code)
    self.code = code
    return self
end

--- @type fun(self: ReportAPI, message: string): ReportAPI
function Report:with_message(message)
    self.message = message
    return self
end

--- @type fun(self: ReportAPI, cache: Cache): string
function Report:render(cache) return render(self, cache) end

-- #endregion

---@class (exact) Ariadne
return {
    Cache = Cache,
    Source = Source,
    ColorGenerator = ColorGenerator,
    Characters = characters,
    Config = Config,
    Label = Label,
    Report = Report,
}
