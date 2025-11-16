---@class utf8
---@field len fun(s: string, i?: integer, j?: integer): integer?
---@field offset fun(s: string, n: integer, i?: integer): integer?, integer?
---@field width fun(s: string, i?: integer, j?:integer, ambiwidth?: integer, fallback: integer?): integer
---@field width fun(ch: integer, ambiwidth?: integer, fallback: integer?): integer
---@field widthindex fun(s: string, width?: integer, i?: integer, j?:integer, ambiwidth?: integer, fallback: integer?): integer, integer, integer
---@field widthlimit fun(s: string, limit?: integer, i?: integer, j?:integer, ambiwidth?: integer, fallback: integer?): integer, integer
---@field codepoint fun(s: string, i?: integer, j?: integer, lax?: boolean): integer
local utf8 = require "lua-utf8"

local MIN_FILENAME_WIDTH = 8

--- Creates a new class
---@generic T
---@param name string
---@param t T?
---@return T
local function class(name, t)
    t = t or {}
    t.__name = name
    t.__index = t
    return t
end

--- @class Cache
local Cache = class "Cache"
do
    ---@return Cache
    function Cache.new()
        return setmetatable({}, Cache)
    end

    --- @param id string
    --- @return Source?
    function Cache:fetch(id)
        return self[id]
    end
end

--- @class (exact) Line
--- @field new fun(offset: integer, len: integer, byte_offset: integer,
---                byte_len: integer, newline: boolean): Line
--- @field offset       integer offset of this line in the original [`Source`]
--- @field len          integer character length of this line
--- @field byte_offset  integer byte offset of this line in the original [`Source`]
--- @field private byte_len     integer byte length of this line in the original [`Source`]
--- @field private newline      boolean whether this line ends with a newline
local Line = class "Line"
do
    --- creates a new Line
    ---@param offset integer
    ---@param len integer
    ---@param byte_offset integer
    ---@param byte_len integer
    ---@param newline boolean
    ---@return Line
    function Line.new(offset, len, byte_offset, byte_len, newline)
        return setmetatable({
            offset = offset,
            len = len,
            byte_offset = byte_offset,
            byte_len = byte_len,
            newline = newline,
        }, Line)
    end

    --- Return the length of this line including the newline character
    --- @type fun(self: Line): integer
    function Line:len_with_newline()
        return self.len + (self.newline and 1 or 0)
    end

    --- returns the span of this line in the original [`Source`]
    --- @type fun(self: Line): integer, integer
    function Line:span()
        return self.offset, self.offset + self.len - 1
    end

    --- checks if a position is within the span of this line
    --- @type fun(self: Line, pos: integer): boolean
    function Line:span_contains(pos)
        return pos >= self.offset and pos <= self.offset + self.len
    end

    --- returns the byte span of this line in the original [`Source`]
    --- @type fun(self: Line): integer, integer
    function Line:byte_span()
        return self.byte_offset, self.byte_offset + self.byte_len - 1
    end

    --- Returns the column number for a given offset
    --- @param offset integer
    --- @return integer
    function Line:col(offset)
        return offset - self.offset + 1
    end

    --- Check if an offset is within any of the multiline labels
    --- @type fun(self: Line, multi_labels: LabelInfo[]): boolean
    function Line:is_within_label(multi_labels)
        for _, info in ipairs(multi_labels) do
            if info.start_char < self.offset and info.end_char > self.offset then
                return true
            end
        end
        return false
    end
end

--- @class (exact) Source : Cache
--- @field new fun(code: string, name?: string, offset?: integer): Source
--- @field private id       string
--- @field private text string the original source text
--- @field private display_line_offset integer
--- @field [integer] Line
local Source = class "Source"
do
    --- Splits the source code into lines
    ---@param code string
    ---@return Line[]
    ---@return integer total_chars
    ---@return integer total_bytes
    local function split_code(code)
        if #code == 0 then
            return { Line.new(1, 0, 1, 0, false), }, 0, 0
        end
        local lines = {}
        local chars, bytes = 0, 0
        for ends in code:gmatch "()\n" do
            local chars_len = assert(utf8.len(code, bytes + 1, ends - 1))
            local bytes_len = ends - bytes - 1
            lines[#lines + 1] = Line.new(chars + 1, chars_len,
                bytes + 1, bytes_len, true)
            chars = chars + chars_len + 1
            bytes = ends --[[@as integer]]
        end
        local chars_len = assert(utf8.len(code, bytes + 1, #code))
        local bytes_len = #code - bytes
        lines[#lines + 1] = Line.new(chars + 1, chars_len, bytes + 1, bytes_len, false)
        return lines, chars + chars_len, bytes + bytes_len
    end

    --- creates a new Source
    ---@param code string
    ---@param name? string
    ---@param offset? integer
    ---@return Source
    function Source.new(code, name, offset)
        ---@type Source
        local src, chars, bytes = split_code(code)
        src.text = code
        src.id = name or "<unknown>"
        src.display_line_offset = offset or 0
        return setmetatable(src, Source)
    end

    --- implements [`Cache:fetch`]
    ---@param _ string
    ---@return Source?
    function Source:fetch(_) return self end

    --- binary_search locates the greatest line index whose key is <= target.
    ---@param lines Line[]
    ---@param target integer
    ---@param key string
    ---@return integer
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

    --- returns the line, its index, and the character position
    --- within the line for a given offset
    ---@param offset integer
    ---@return integer index
    function Source:get_offset_line(offset)
        return binary_search(self, offset, "offset")
    end

    --- returns the line and index, by the bytes position
    ---@param byte_offset integer
    ---@return integer index
    function Source:get_byte_line(byte_offset)
        return binary_search(self, byte_offset, "byte_offset")
    end

    --- Get the line number offseted by display_line_offset
    ---@param line_no integer
    ---@return integer
    function Source:offseted_line_no(line_no)
        return line_no + self.display_line_offset
    end

    --- Find the character that should be drawn and the number of times it
    --- should be drawn for each char
    --- @param byte_offset integer
    --- @param col integer
    --- @param cfg Config
    --- @return integer repeat_count
    --- @return integer codepoint
    function Source:char_width(byte_offset, col, cfg)
        local c = utf8.codepoint(self.text, utf8.offset(self.text, col, byte_offset))
        if c == 9 then -- tab
            return cfg.tab_width - ((col - 1) % cfg.tab_width), 32
        elseif c == 32 then
            return 1, 32
        else
            return utf8.width(c), c
        end
    end

    ---@type fun(self: Source): string
    function Source:src_id() return self.id end

    --- @type fun(self: Source, i: integer, j: integer): integer?
    function Source:utf8_len(i, j) return utf8.len(self.text, i, j) end

    --- @type fun(self: Source, i: integer, j: integer): integer?
    function Source:utf8_width(i, j) return utf8.width(self.text, i, j) end

    --- @type fun(self: Source, n: integer, i: integer): integer?, integer?
    function Source:utf8_offset(n, i) return utf8.offset(self.text, n, i) end

    --- @type fun(self: Source, i: integer, j: integer): string
    function Source:utf8_sub(i, j) return self.text:sub(i, j) end

    --- @type fun(self: Source, width: integer, i: integer, j: integer,
    ---           ambiwidth?: integer, fallback?: integer): integer, integer, integer
    function Source:utf8_widthindex(width, i, j, ambiwidth, fallback)
        return utf8.widthindex(self.text, width, i, j, ambiwidth, fallback)
    end
end


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

---@type table
local Characters = {}
do
    ---@type CharSet
    Characters.unicode = setmetatable({
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
    }, Characters)

    ---@type CharSet
    Characters.ascii = setmetatable({
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
    }, Characters)
end

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
--- @field private state integer[]
--- @field private min_brightness number
local ColorGenerator = class "ColorGenerator"
do
    --- creates a new ColorGenerator
    ---@return ColorGenerator
    function ColorGenerator.new()
        return setmetatable({
            state = { 30000, 15000, 35000 },
            min_brightness = 0.5,
        }, ColorGenerator)
    end

    --- returns the next color code
    ---@return integer
    function ColorGenerator:next()
        for i = 1, #self.state do
            self.state[i] = self.state[i] + 40503 * (i * 4 + 1130)
            self.state[i] = self.state[i] % 65536
        end
        return 16 + ((self.state[3] / 65535 * (1 - self.min_brightness)
                + self.min_brightness) * 5.0)
            + ((self.state[2] / 65535 * (1 - self.min_brightness)
                + self.min_brightness) * 30.0)
            + ((self.state[1] / 65535 * (1 - self.min_brightness)
                + self.min_brightness) * 180.0)
    end
end

--- @class Config
--- @field default Config
--- @field cross_gap        boolean
--- @field label_attach     "start" | "end" | "middle"
--- @field compact          boolean
--- @field underlines       boolean
--- @field multiline_arrows boolean
--- @field color?           Color
--- @field tab_width        integer
--- @field char_set         CharSet
--- @field index_type       "byte" | "char"
--- @field line_width?      integer
local Config = class "Config"
do
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

    Config.default = setmetatable({
        cross_gap = true,
        label_attach = "middle",
        compact = false,
        underlines = true,
        multiline_arrows = true,
        color = default_color,
        tab_width = 4,
        char_set = Characters.unicode,
        index_type = "char",
        line_width = nil, -- nil = no limit, positive integer = max width
    }, Config)

    --- creates a new Config
    ---@param options table
    ---@return Config
    function Config.new(options)
        options = options or {}
        for k, v in pairs(Config.default) do
            if options[k] == nil then
                options[k] = v
            end
        end
        return setmetatable(options, Config)
    end
end

--- @class (exact) Label
--- @field new fun(start_pos: integer, end_pos?: integer, source_id?: string,
---              message?: string, color?: Color, order?: integer, priority?: integer): Label
--- @field start_pos  integer
--- @field end_pos?   integer
--- @field source_id? string
--- @field message?   string
--- @field width?     integer
--- @field color?     Color
--- @field order      integer
--- @field priority   integer
local Label = class "Label"
do
    --- creates a new Label
    ---@param start_pos integer start offset (bytes or chars)
    ---@param end_pos? integer end offset (bytes or chars)
    ---@param source_id? string source identifier
    ---@param message? string label message
    ---@param color? Color label color
    ---@param order? integer label order
    ---@param priority? integer label priority
    ---@return Label
    function Label.new(start_pos, end_pos, source_id, message, color, order, priority)
        return setmetatable({
            start_pos = start_pos,
            end_pos = end_pos,
            source_id = source_id,
            message = message,
            color = color,
            order = order or 0,
            priority = priority or 0,
        }, Label)
    end

    --- returns the byte span of this label
    ---@return integer
    ---@return integer?
    function Label:span()
        return self.start_pos, self.end_pos
    end

    ---@param msg string
    ---@return Label
    function Label:with_message(msg, width)
        self.message = msg
        self.width = width
        return self
    end

    ---@param color Color
    ---@return Label
    function Label:with_color(color)
        self.color = color
        return self
    end

    ---@param order integer
    ---@return Label
    function Label:with_order(order)
        self.order = order
        return self
    end

    ---@param priority integer
    ---@return Label
    function Label:with_priority(priority)
        self.priority = priority
        return self
    end
end

--- @class (exact) Report
--- @field build fun(kind: string, pos: integer, source_id?: string): Report
--- @field kind string
--- @field code? string
--- @field message? string
--- @field notes string[]
--- @field helps string[]
--- @field pos integer
--- @field id? string
--- @field labels Label[]
--- @field config Config
local Report = class "Report"
do
    --- creates a new Report
    ---@param kind string
    ---@param pos integer
    ---@param id? string
    ---@return Report
    function Report.build(kind, pos, id)
        return setmetatable({
            kind = kind,
            code = nil,
            message = nil,
            notes = {},
            helps = {},
            pos = pos,
            id = id,
            labels = {},
            config = Config.default,
        }, Report)
    end

    ---@param code string
    ---@return Report
    function Report:with_code(code)
        self.code = code
        return self
    end

    ---@param message string
    ---@return Report
    function Report:with_message(message)
        self.message = message
        return self
    end

    ---@param note string
    ---@return Report
    function Report:with_note(note)
        self.notes[#self.notes + 1] = note
        return self
    end

    ---@param help string
    ---@return Report
    function Report:with_help(help)
        self.helps[#self.helps + 1] = help
        return self
    end

    ---@param label Label
    ---@return Report
    function Report:with_label(label)
        self.labels[#self.labels + 1] = label
        return self
    end

    ---@param config Config
    ---@return Report
    function Report:with_config(config)
        self.config = config
        return self
    end
end

---@class (exact) Writer
---@field config Config
---@field cur_color Color?
---@field cur_color_code string?
---@field new fun(config: Config): Writer
---@field reset fun(self: Writer, s?: any): Writer
---@field error fun(self: Writer, s?: any): Writer
---@field warning fun(self: Writer, s?: any): Writer
---@field kind fun(self: Writer, s?: any): Writer
---@field margin fun(self: Writer, s?: any): Writer
---@field skipped_margin fun(self: Writer, s?: any): Writer
---@field unimportant fun(self: Writer, s?: any): Writer
---@field note fun(self: Writer, s?: any): Writer
---@field label fun(self: Writer, s?: any): Writer
---@field tostring fun(self: Writer): string
---@operator call(string): Writer
local Writer = class "Write"
do
    --- creates a new Writer
    ---@param config Config
    ---@return Writer
    function Writer.new(config)
        return setmetatable({ config = config }, Writer)
    end

    ---@param s any
    ---@return Writer
    function Writer:__call(s)
        self[#self + 1] = s
        return self
    end

    ---@param color Color?
    ---@return Writer
    function Writer:use_color(color)
        color = color or self.config.color
        if self.cur_color_code and color ~= self.cur_color then
            self:reset()
        end
        self.cur_color = color
        return self
    end

    for _, category in ipairs {
        "error",
        "warning",
        "kind",
        "margin",
        "skipped_margin",
        "unimportant",
        "note",
        "label",
        "default",
    } do
        ---@param self Writer
        ---@param s any
        ---@return Writer
        Writer[category] = function(self, s)
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

    ---@param s any
    ---@return Writer
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
    ---@param count integer
    ---@param s any
    ---@return Writer
    function Writer:padding(count, s)
        if count > 0 then
            self[#self + 1] = (s or ' '):rep(count)
        end
        return self
    end

    --- Write s when not in compact mode
    ---@param s any
    ---@return Writer
    function Writer:compact(s)
        if not self.config.compact then
            self[#self + 1] = s
        end
        return self
    end

    ---@param cur_color Color?
    ---@param s any
    ---@return Writer
    function Writer:label_or_unimportant(cur_color, s)
        if cur_color then
            return self:use_color(cur_color):label(s)
        end
        return self:unimportant(s)
    end

    --- draw a empty line
    ---@param line_no_width integer
    function Writer:empty_line(line_no_width)
        local cfg = self.config
        local draw = cfg.char_set
        if not cfg.compact then
            self:padding(line_no_width + 2):margin(draw.vbar):reset "\n"
        end
    end

    ---@return string
    function Writer:tostring()
        return table.concat(self)
    end
end

---@class (exact) LabelInfo
---@field new fun(label: Label, src: Source, index_type: "byte" | "char"): LabelInfo?
---@field multi boolean
---@field start_char integer
---@field end_char? integer
---@field label Label
local LabelInfo = class "LabelInfo"
do
    --- creates a new LabelInfo
    ---@param label Label
    ---@param src Source
    ---@param index_type "byte" | "char"
    ---@return LabelInfo?
    function LabelInfo.new(label, src, index_type)
        -- find label line and character positions
        local given_start, given_end = label:span()
        ---@type integer, integer?, Line, Line
        local label_start_char, label_end_char, start_line, end_line
        if index_type == "char" then
            start_line = assert(src[src:get_offset_line(given_start)],
                "label start position out of range")
            label_start_char = given_start
            if given_end and given_start <= given_end then
                end_line = assert(src[src:get_offset_line(given_end)])
                label_end_char = given_end
            else
                end_line = start_line
            end
        else
            local line_no = src:get_byte_line(given_start)
            start_line = assert(src[line_no], "start byte offset out of range")
            label_start_char = start_line.offset +
                assert(src:utf8_len(start_line.byte_offset, given_start - 1))
            if given_end and given_start <= given_end then
                line_no = src:get_byte_line(given_end)
                end_line = assert(src[line_no], "end byte offset out of range")
                label_end_char = end_line.offset +
                    assert(src:utf8_len(end_line.byte_offset, given_end)) - 1
            else
                end_line = start_line
            end
        end

        if label_start_char > start_line.offset + start_line.len then
            return nil
        end
        return setmetatable({
            multi = start_line ~= end_line,
            start_char = label_start_char,
            end_char = label_end_char,
            label = label,
        }, LabelInfo)
    end
end

--- @class (exact) LineLabel
--- @field col integer
--- @field info LabelInfo
--- @field draw_msg boolean

---@class (exact) LabelCluster
---@field new fun(idx: integer, line: Line, group: SourceGroup,
---               ctx: RenderContext, cfg: Config): LabelCluster?
---@field private line Line
---@field private line_no integer
---@field private margin_label LineLabel?
---@field private line_labels LineLabel[]
---@field private arrow_len integer
---@field private start_col integer
---@field private end_col? integer
local LabelCluster = class "LabelCluster"
do
    --- Get the margin label for a line.
    ---
    --- Which is the most significant multiline label on this line.
    --- It's the multiline label with the minimum column (start or end),
    --- if columns are equal, the one with the maximum start position is chosen.
    ---@param line Line
    ---@param group SourceGroup
    ---@return LineLabel?
    local function get_margin_label(line, group)
        ---@type integer?, LabelInfo?, boolean?
        local col, info, draw_msg
        for i, cur_info in group:iter_margin_labels() do
            local cur_col, cur_draw_msg
            if line:span_contains(cur_info.start_char) then
                cur_col = line:col(cur_info.start_char)
                cur_draw_msg = false
            elseif cur_info.end_char and line:span_contains(cur_info.end_char) then
                cur_col = line:col(cur_info.end_char)
                cur_draw_msg = true
            end
            -- find the minimum column or maximum start pos if columns are equal
            -- label as the margin label
            if cur_col and (not col or not info or cur_col < col or (cur_col == col
                    and cur_info.start_char > info.start_char)) then
                col, info, draw_msg = cur_col, cur_info, cur_draw_msg
            end
        end
        if not col then return nil end
        return { col = col, info = info, draw_msg = draw_msg }
    end

    --- Collect multiline labels for a specific line
    ---@param line_labels LineLabel[]
    ---@param line Line
    ---@param margin_label LineLabel?
    ---@param group SourceGroup
    local function collect_multi_labels_in_line(line_labels, line, margin_label, group)
        for i, info in group:iter_margin_labels() do
            local col, draw_msg
            if line:span_contains(info.start_char)
                and (not margin_label or info ~= margin_label.info)
            then
                line_labels[#line_labels + 1] = {
                    col = line:col(info.start_char),
                    info = info,
                    draw_msg = false,
                }
            elseif info.end_char and line:span_contains(info.end_char) then
                line_labels[#line_labels + 1] = {
                    col = line:col(info.end_char),
                    info = info,
                    draw_msg = true,
                }
            end
        end
    end

    --- Collect inline labels for a specific line
    ---@param line_labels LineLabel[]
    ---@param line Line
    ---@param group SourceGroup
    ---@param label_attach "start" | "end" | "middle"
    local function collect_labels_in_line(line_labels, line, group, label_attach)
        local _, end_char = line:span()
        for _, info in group:iter_labels() do
            if not info.multi and info.start_char >= line.offset and
                (info.end_char or info.start_char) <= end_char + 1
            then
                local col = info.start_char
                if label_attach == "end" then
                    col = info.end_char or info.start_char
                elseif label_attach == "middle" and info.end_char then
                    col = (info.start_char + info.end_char + 1) // 2
                end
                line_labels[#line_labels + 1] = {
                    col = line:col(col),
                    info = info,
                    draw_msg = true,
                }
            end
        end
    end

    ---@param line_labels LineLabel[]
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

    --- Calculate the maximum arrow line length for a specific line
    ---@param line Line
    ---@param margin_label LineLabel?
    ---@param line_labels LineLabel[]
    ---@param compact boolean
    ---@return integer arrow_len
    ---@return integer min_col
    ---@return integer max_label_width
    local function calc_arrow_len(line, margin_label, line_labels, compact)
        local arrow_end_space = compact and 1 or 2
        local arrow_len, max_width = 0, 0
        local min_col
        for _, ll in ipairs(line_labels) do
            if ll.info.multi then
                arrow_len = line:len_with_newline()
            else
                local cur = line:col(ll.info.end_char or ll.info.start_char - 1)
                if arrow_len < cur then
                    arrow_len = cur
                end
            end
            local msg_width = ll.info.label.width
            if not msg_width then
                msg_width = utf8.width(ll.info.label.message or "")
            end
            if max_width < msg_width then
                max_width = msg_width
            end
            local cur_col = ll.col
            if not ll.info.multi then
                cur_col = line:col(ll.info.start_char)
            end
            if (not margin_label or margin_label.info ~= ll.info) and
                (not min_col or cur_col < min_col)
            then
                min_col = cur_col
            end
        end
        return arrow_len + arrow_end_space, min_col, max_width
    end

    --- Calculate the start position for rendering a line
    ---@param arrow_len integer
    ---@param min_col integer
    ---@param max_label_width integer
    ---@param group SourceGroup
    ---@param ctx RenderContext
    ---@param cfg Config
    ---@return integer start_col
    ---@return integer? end_col
    local function calc_col_range(line, arrow_len, min_col, max_label_width,
                                  group, ctx, cfg)
        if not cfg.line_width then return 1 end
        local src = group:get_source()
        local line_no_width = ctx.line_no_width
        local ellipsis_width = ctx.ellipsis_width

        local margin_count = group:margin_len()
        local fix_width = line_no_width + 4 +       -- line no and margin
            margin_count * (cfg.compact and 1 or 2) -- margin arrows
        local line_width = cfg.line_width - fix_width

        -- the width of arrows line:
        --                          |<-- min_width ->|
        --  1 | ...aaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbb...
        --    |                     ^^|^^
        --    |                       `---- found here
        --                          ^ min_col  ...-->| arrow_limit
        --                                ^ arrow_len (arrow_width)
        -- line.len may be less than arrow_len
        local extra = math.max(0, arrow_len - line.len)
        local _, arrow_end = src:utf8_offset(arrow_len, line.byte_offset)
        local line_end = line.byte_offset + line.byte_len - 1
        if not arrow_end then arrow_end = line_end end
        local arrow_width = src:utf8_width(line.byte_offset, arrow_end) + extra
        local arrow_limit = arrow_width + 1 + max_label_width -- 1: space before msg

        -- all line fits in line_width? No need to skip
        local total_width = src:utf8_width(line.byte_offset, line_end)
        if arrow_limit <= line_width and total_width <= line_width then return 1 end

        -- min_col already overflow? Using min_col
        local min_width = src:utf8_width(
                assert(src:utf8_offset(min_col, line.byte_offset)), arrow_end) +
            1 + max_label_width
        if min_width + ellipsis_width >= line_width then
            return min_col, math.min(line.len, arrow_len + (src:utf8_widthindex(
                1 + max_label_width - ellipsis_width,
                arrow_end + 1, line_end)))
        end

        local min_skip = arrow_limit - line_width + ellipsis_width + 1
        if min_skip <= 0 then
            return 1, math.min(line.len, arrow_len + (src:utf8_widthindex(
                line_width - arrow_width - ellipsis_width,
                arrow_end + 1, line_end)))
        end
        local balance_skip = 0
        if total_width > arrow_limit then
            local avail_width = total_width - arrow_limit
            local right_width = (line_width - min_width) // 2
            balance_skip = right_width + math.max(0, right_width - avail_width)
        end
        local start_col = (src:utf8_widthindex(min_skip + balance_skip,
            line.byte_offset, arrow_end))
        local end_col, idx, chwidth = src:utf8_widthindex(
            1 + max_label_width + balance_skip - ellipsis_width,
            arrow_end + 1, line_end)
        -- multi width in the end_col edge?
        if idx ~= chwidth then end_col = end_col - 1 end
        return start_col, math.min(line.len, arrow_len + end_col)
    end

    --- creates a new LabelCluster
    ---@param idx integer
    ---@param line Line
    ---@param group SourceGroup
    ---@param ctx RenderContext
    ---@return LabelCluster?
    function LabelCluster.new(idx, line, group, ctx, cfg)
        local margin_label = get_margin_label(line, group)

        -- Generate a list of labels for this line, along with their label columns
        ---@type LineLabel[]
        local line_labels = {}
        collect_multi_labels_in_line(line_labels, line, margin_label, group)
        collect_labels_in_line(line_labels, line, group, cfg.label_attach)
        sort_line_labels(line_labels)

        if #line_labels == 0 and not margin_label then return nil end
        local arrow_len, min_col, max_label_width =
            calc_arrow_len(line, margin_label, line_labels, cfg.compact)
        local start_col, end_col = calc_col_range(
            line, arrow_len, min_col or 1, max_label_width,
            group, ctx, cfg)
        return setmetatable({
            line_no = group:get_source():offseted_line_no(idx),
            line = line,
            margin_label = margin_label,
            line_labels = line_labels,
            arrow_len = arrow_len,
            start_col = start_col,
            end_col = end_col,
        }, LabelCluster)
    end

    --- Get the highest priority highlight for a column
    ---@private
    ---@param col integer
    ---@param group SourceGroup
    ---@return LabelInfo?
    function LabelCluster:get_highlight(col, group)
        local result
        local offset = self.line.offset + col - 1

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

        if self.margin_label then
            update_result(self.margin_label.info)
        end
        for _, info in group:iter_multi_labels() do
            update_result(info)
        end
        for _, ll in ipairs(self.line_labels) do
            if ll.info.end_char then
                update_result(ll.info)
            end
        end
        return result
    end

    --- Render a line with highlights
    ---@param W Writer
    ---@param group SourceGroup
    ---@param cfg Config
    function LabelCluster:render_line(W, group, cfg)
        local line = self.line
        local src = group:get_source()

        --- @type Color?
        local cur_color
        local cur_offset = self.start_col
        local cur_offset_byte = assert(src:utf8_offset(
            self.start_col, line.byte_offset))
        for i = self.start_col, self.end_col or line.len do
            local highlight = self:get_highlight(i, group)
            local next_color = highlight and highlight.label.color
            local repeat_count, cp = group:get_source():char_width(
                line.byte_offset, i, cfg)
            if cur_color ~= next_color or (cp == 32 and repeat_count > 1) then
                local next_start_bytes = assert(src:utf8_offset(
                    i - cur_offset + 1, cur_offset_byte))
                if i > cur_offset then
                    W:label_or_unimportant(cur_color, (src:utf8_sub(
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
        local _, end_bytes = line:byte_span()
        if self.end_col and self.end_col < line.len then
            end_bytes = assert(src:utf8_offset(self.end_col + 1, line.byte_offset)) - 1
        end
        W:label_or_unimportant(cur_color, (src:utf8_sub(
            cur_offset_byte, end_bytes
        ):gsub("\t", ""))):reset()
    end

    --- Should we draw a vertical bar as part of a label arrow on this line?
    ---@private
    ---@param col integer
    ---@param row integer
    ---@return LineLabel?
    function LabelCluster:get_vbar(col, row)
        for i, ll in ipairs(self.line_labels) do
            if ll.info.label.message and not self:is_margin_label(ll.info) and
                ll.col == col and row <= i then
                return ll
            end
        end
    end

    --- Should we draw an underline as part of a label arrow on this line?
    ---@private
    ---@param col integer
    ---@param cfg Config
    ---@return LineLabel?
    function LabelCluster:get_underline(col, cfg)
        if not cfg.underlines then
            return nil
        end
        local offset = self.line.offset + col - 1
        ---@type LineLabel?
        local result
        for i, ll in ipairs(self.line_labels) do
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

    --- Check if the given label info is the margin label
    ---@param info LabelInfo
    ---@return boolean
    function LabelCluster:is_margin_label(info)
        return self.margin_label and self.margin_label.info == info or false
    end

    --- Render arrows for a line
    ---@private
    ---@param W Writer
    ---@param group SourceGroup
    ---@param ctx RenderContext
    function LabelCluster:render_arrows(W, group, ctx)
        local cfg = W.config
        local draw = cfg.char_set

        -- Arrows
        for row, ll in ipairs(self.line_labels) do
            -- No message to draw thus no arrow to draw
            if ll.info.label.message then
                if not W.config.compact then
                    -- Margin alternate
                    ctx:render_lineno(W, nil, false)
                    group:render_margin(W, self.line, false, false,
                        self.margin_label, self.line_labels, ll, false)
                    if self.start_col > 1 then W:padding(ctx.ellipsis_width) end
                    for col = self.start_col, self.arrow_len do
                        local width = 1
                        if col <= self.line.len then
                            width = group:get_source():char_width(
                                self.line.byte_offset, col, cfg)
                        end
                        local vbar = self:get_vbar(col, row)
                        local underline
                        if row == 1 then
                            underline = self:get_underline(col, cfg)
                        end
                        if vbar and underline then
                            local a = draw.underbar
                            W:use_color(vbar.info.label.color):label(a)
                            W:padding(width - 1, draw.underline)
                        elseif vbar then
                            local a = draw.vbar
                            if vbar.info.multi and row == 1 and cfg.multiline_arrows then
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
                ctx:render_lineno(W, nil, false)
                group:render_margin(W, self.line, false, false,
                    self.margin_label, self.line_labels, ll, true)

                -- Lines
                if self.start_col > 1 then W:padding(ctx.ellipsis_width) end
                for col = self.start_col, self.arrow_len do
                    local width = 1
                    if col <= self.line.len then
                        width = group:get_source():char_width(
                            self.line.byte_offset, col, cfg)
                    end
                    local is_hbar = (col > ll.col) ~= ll.info.multi or
                        ll.draw_msg and col > ll.col
                    local vbar = self:get_vbar(col, row)
                    if col == ll.col and not self:is_margin_label(ll.info) then
                        local a = draw.rbot
                        if not ll.info.multi then
                            a = draw.lbot
                        elseif ll.draw_msg then
                            a = draw.mbot
                        end
                        W:use_color(ll.info.label.color):label(a):padding(width - 1, draw.hbar)
                    elseif vbar and col ~= ll.col then
                        local a, b = draw.vbar, ' '
                        if is_hbar then
                            a = draw.xbar
                            if cfg.cross_gap then
                                a, b = draw.hbar, draw.hbar
                            end
                        elseif vbar.info.multi and row == 1 and cfg.compact then
                            a = draw.uarrow
                        end
                        W:use_color(vbar.info.label.color):label(a):padding(width - 1, b)
                    elseif is_hbar then
                        W:use_color(ll.info.label.color):label():padding(width, draw.hbar)
                    else
                        W:reset():padding(width)
                    end
                end
                W:reset()
                if ll.draw_msg then
                    W " " (ll.info.label.message)
                end
                W "\n"
            end
        end
    end

    --- Render a label cluster
    ---@param W Writer
    ---@param group SourceGroup
    ---@param ctx RenderContext
    function LabelCluster:render(W, group, ctx)
        -- Determine label bounds so we know where to put error messages
        local cfg = W.config
        local draw = cfg.char_set

        ctx:render_lineno(W, self.line_no, false)
        group:render_margin(W, self.line, true, false,
            self.margin_label, self.line_labels, nil, false)
        if self.start_col > 1 then
            W:unimportant(draw.ellipsis):reset()
        end
        self:render_line(W, group, cfg)
        if self.end_col and self.end_col < self.line.len then
            W:unimportant(draw.ellipsis):reset()
        end
        W "\n"

        self:render_arrows(W, group, ctx)
    end
end

---@class (exact) SourceGroup
---@field new fun(src: Source): SourceGroup
---@field private src Source
---@field private start_char integer
---@field private end_char? integer
---@field private labels LabelInfo[]
---@field private multi_labels LabelInfo[]
---@field private multi_labels_with_message LabelInfo[]
local SourceGroup = class "SourceGroup"
do
    --- creates a new SourceGroup
    ---@param src Source
    ---@return SourceGroup
    function SourceGroup.new(src)
        return setmetatable({
            src = src,
            start_char = nil,
            end_char = nil,
            labels = {},
            multi_labels = {},
            multi_labels_with_message = {},
        }, SourceGroup)
    end

    --- Get the number of multiline labels with messages
    ---@return integer
    function SourceGroup:margin_len()
        local len = #self.multi_labels_with_message
        return len > 0 and len + 1 or 0
    end

    --- Iterate over multiline labels with messages
    ---@return fun(table: LabelInfo[], i?: integer):integer, LabelInfo
    ---@return LabelInfo[]
    ---@return integer
    function SourceGroup:iter_margin_labels()
        return ipairs(self.multi_labels_with_message)
    end

    --- Iterate over multiline labels
    ---@return fun(table: LabelInfo[], i?: integer):integer, LabelInfo
    ---@return LabelInfo[]
    ---@return integer
    function SourceGroup:iter_multi_labels()
        return ipairs(self.multi_labels)
    end

    --- Iterate over labels
    ---@return fun(table: LabelInfo[], i?: integer):integer, LabelInfo
    ---@return LabelInfo[]
    ---@return integer
    function SourceGroup:iter_labels()
        return ipairs(self.labels)
    end

    --- Get the source of the source group
    --- @return Source
    function SourceGroup:get_source()
        return self.src
    end

    --- Add label information to the source group
    ---@param info LabelInfo
    function SourceGroup:add_label_info(info)
        if not self.start_char or info.start_char < self.start_char then
            self.start_char = info.start_char
        end
        if info.end_char and (not self.end_char
                or info.end_char > self.end_char) then
            self.end_char = info.end_char
        end
        self.labels[#self.labels + 1] = info
    end

    --- Collect multiline labels
    function SourceGroup:collect_multi_labels()
        local multi_labels = self.multi_labels
        local multi_labels_with_message = self.multi_labels_with_message

        for _, info in ipairs(self.labels) do
            if info.multi then
                multi_labels[#multi_labels + 1] = info
                if info.label.message then
                    multi_labels_with_message[#multi_labels_with_message + 1] = info
                end
            end
        end

        -- Sort labels by length
        table.sort(multi_labels_with_message, function(a, b)
            local alen = a.end_char - a.start_char + 1
            local blen = b.end_char - b.start_char + 1
            return alen > blen
        end)
    end

    --- Get the last line number of the source group
    ---@return integer
    function SourceGroup:last_line_no()
        local src = self.src
        return src:offseted_line_no(
            src:get_offset_line(self.end_char or self.start_char))
    end

    --- Calculate the line and column string for a report position
    ---@private
    ---@param ctx_id string
    ---@param ctx_pos integer
    ---@param cfg Config
    ---@return string
    function SourceGroup:calc_location(ctx_id, ctx_pos, cfg)
        local src = self.src
        ---@type Line?, integer?, integer?
        local line, line_no, col_no
        if not ctx_id or self.src:src_id() == ctx_id then
            if cfg.index_type == "byte" then
                line_no = src:get_byte_line(ctx_pos)
                line = assert(src[line_no], "byte offset out of range")
                local _, line_byte_end = line:byte_span()
                if line and ctx_pos <= line_byte_end then
                    col_no = assert(src:utf8_len(line.byte_offset, ctx_pos - 1)) + 1
                else
                    line_no = nil
                end
            else
                line_no = src:get_offset_line(ctx_pos)
                line = src[line_no]
                if line then
                    col_no = line:col(ctx_pos)
                end
            end
        else
            local start = self.labels[1].start_char
            line_no = src:get_offset_line(start)
            line = src[line_no]
            if line then
                col_no = line:col(start)
            end
        end
        if not line_no then return "?:?" end
        return ("%d:%d"):format(src:offseted_line_no(line_no), col_no)
    end

    --- Render the reference line for a source group
    ---@param W Writer
    ---@param idx integer
    ---@param ctx RenderContext
    function SourceGroup:render_reference(W, idx, ctx)
        local cfg = W.config
        local draw = cfg.char_set
        local id = self.src:src_id():gsub("\t", " ")
        local loc = self:calc_location(ctx.id, ctx.pos, cfg)
        if cfg.line_width then
            local id_width = utf8.width(id)
            -- assume draw's components' width are all 1
            local fixed_width = utf8.width(loc) + ctx.line_no_width + 9
            if id_width + fixed_width > cfg.line_width then
                local avail = cfg.line_width - fixed_width - ctx.ellipsis_width
                if avail < MIN_FILENAME_WIDTH then
                    avail = MIN_FILENAME_WIDTH
                end
                id = draw.ellipsis .. id:sub((utf8.widthlimit(id, -avail)))
            end
        end
        W:padding(ctx.line_no_width + 2)
        W:margin(idx == 1 and draw.ltop or draw.vbar)
        W(draw.hbar)(draw.lbox):reset " "
        W(id) ":" (loc) " ":margin(draw.rbox):reset "\n"
    end

    --- Render the margin arrows for a specific line
    ---@param W Writer
    ---@param line Line
    ---@param is_line boolean
    ---@param is_ellipsis boolean
    ---@param margin_label? LineLabel
    ---@param line_labels? LineLabel[]
    ---@param report_row? LineLabel
    ---@param report_row_is_arrow boolean
    function SourceGroup:render_margin(W, line, is_line, is_ellipsis,
                                       margin_label, line_labels,
                                       report_row, report_row_is_arrow)
        if #self.multi_labels_with_message == 0 then
            return
        end

        local draw = W.config.char_set
        local _, end_char = line:span()

        ---@type LabelInfo?, LabelInfo?
        local hbar, margin_ptr
        local margin_ptr_is_start = false

        for _, info in ipairs(self.multi_labels_with_message) do
            ---@type LabelInfo?, LabelInfo?
            local vbar, corner

            local is_start = line:span_contains(info.start_char)
            if info.start_char <= end_char and info.end_char >= line.offset then
                local is_margin = margin_label and info == margin_label.info
                local is_end = line:span_contains(info.end_char)
                if is_margin and is_line then
                    margin_ptr, margin_ptr_is_start = info, is_start
                elseif not is_start and (not is_end or is_line) then
                    vbar = info
                elseif report_row then
                    if report_row.info == info then
                        if not report_row_is_arrow and not is_start then
                            vbar = info
                        elseif is_margin then
                            vbar = assert(margin_label).info
                        end
                        if report_row_is_arrow and (not is_margin or not is_start) then
                            hbar, corner = info, info
                        end
                    else
                        local report_row_is_before = 0
                        for j, ll in ipairs(assert(line_labels)) do
                            if ll.info == report_row.info then
                                report_row_is_before = 2
                            end
                            if ll.info == info then
                                if report_row_is_before == 2 then
                                    report_row_is_before = 1
                                end
                                break
                            end
                        end
                        if is_start ~= (report_row_is_before == 1) then
                            vbar = info
                        end
                    end
                end
            end

            if margin_ptr and is_line and info ~= margin_ptr then
                hbar = hbar or margin_ptr
            end

            if corner then
                local a = is_start and draw.ltop or draw.lbot
                W:use_color(corner.label.color):label(a):compact(draw.hbar)
            elseif vbar and hbar and not W.config.cross_gap then
                W:use_color(vbar.label.color):label(draw.xbar):compact(draw.hbar)
            elseif hbar then
                W:use_color(hbar.label.color):label(draw.hbar):compact(draw.hbar)
            elseif vbar then
                local a = is_ellipsis and draw.vbar_gap or draw.vbar
                W:use_color(vbar.label.color):label(a):compact ' '
            elseif margin_ptr and is_line then
                local a, b = draw.hbar, draw.hbar
                if info and info == margin_ptr then
                    a = margin_ptr_is_start and draw.ltop or draw.lcross
                end
                W:use_color(margin_ptr.label.color):label(a):compact(b)
            else
                W:reset(W.config.compact and ' ' or '  ')
            end
        end
        if hbar and (not is_line or hbar ~= margin_ptr) then
            W:use_color(hbar.label.color):label(draw.hbar):compact(draw.hbar):reset()
        elseif margin_ptr and is_line then
            W:use_color(margin_ptr.label.color):label(draw.rarrow):compact ' ':reset()
        else
            W:reset(W.config.compact and ' ' or '  ')
        end
    end

    --- Render the lines for a source group
    ---@param W Writer
    ---@param ctx RenderContext
    function SourceGroup:render_lines(W, ctx)
        local src = self.src
        local cfg = W.config
        local is_ellipsis = false
        local line_start = src:get_offset_line(self.start_char)
        local line_end = line_start
        if self.end_char then
            line_end = src:get_offset_line(self.end_char)
        end
        for idx = line_start, line_end do
            local line = assert(src[idx], "group line out of range")
            local cluster = LabelCluster.new(idx, line, self, ctx, cfg)

            if cluster then
                cluster:render(W, self, ctx)
            elseif not is_ellipsis and line:is_within_label(self.multi_labels) then
                ctx:render_lineno(W, nil, true)
                self:render_margin(W, line, false, true, nil, nil, nil, false)
                W "\n"
            elseif not W.config.compact and not is_ellipsis then
                -- Skip this line if we don't have labels for it
                ctx:render_lineno(W, nil, false)
                W "\n"
            end
            is_ellipsis = not cluster
        end
    end
end

--- @class (exact) RenderContext
--- @field new fun(id: string, pos: integer, cache: Cache, labels: Label[], cfg: Config): RenderContext
--- @field id string
--- @field pos integer
--- @field groups SourceGroup[]
--- @field cache Cache
--- @field line_no_width integer
--- @field ellipsis_width integer
local RenderContext = class "RenderContext"
do
    --- Calculate the maximum width of line numbers in all source groups
    ---@param groups SourceGroup[]
    ---@return integer
    local function calc_line_no_width(groups)
        local width = 0
        for _, group in ipairs(groups) do
            local line_no = group:last_line_no()
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
    ---@param id string
    ---@param pos integer
    ---@param cache Cache
    ---@param labels Label[]
    ---@param cfg Config
    function RenderContext.new(id, pos, cache, labels, cfg)
        -- group labels by source
        ---@type SourceGroup[]
        local groups = {}
        for _, label in ipairs(labels) do
            local src = assert(cache:fetch(label.source_id), "source not found")
            local info = LabelInfo.new(label, src, cfg.index_type)
            if info then
                local key = label.source_id or id or "<unknown>"
                local group = groups[key]
                if not group then
                    group = SourceGroup.new(src)
                    groups[#groups + 1] = group
                    groups[key] = group
                end
                group:add_label_info(info)
            end
        end

        -- line number maximum width
        local line_no_width = calc_line_no_width(groups)

        -- ellipsis width
        local draw = cfg.char_set
        local ellipsis_width = utf8.width(draw.ellipsis)

        return setmetatable({
            id = id,
            pos = pos,
            groups = groups,
            cache = cache,
            line_no_width = line_no_width,
            ellipsis_width = ellipsis_width,
        }, RenderContext)
    end

    --- Render the header for a report
    ---@param W Writer
    ---@param kind string
    ---@param code string?
    ---@param message string?
    function RenderContext:render_header(W, kind, code, message)
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
    ---@param W Writer
    ---@param line_no integer?
    ---@param is_ellipsis boolean
    function RenderContext:render_lineno(W, line_no, is_ellipsis)
        local draw = W.config.char_set
        if line_no and not is_ellipsis then
            local line_no_str = tostring(line_no)
            W " ":padding(self.line_no_width - #line_no_str)
            W:margin(line_no_str) " " (draw.vbar):reset()
        else
            W " ":padding(self.line_no_width + 1)
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
    ---@private
    ---@param W Writer
    ---@param prefix string
    ---@param items string[]
    function RenderContext:render_help_or_node(W, prefix, items)
        for i, item in ipairs(items) do
            if not W.config.compact then
                self:render_lineno(W, nil, false)
                W "\n"
            end
            local item_prefix = #items > 1 and ("%s %d"):format(prefix, i) or prefix
            local item_prefix_len
            for line in item:gmatch "([^\n]*)\n?" do
                self:render_lineno(W, nil, false)
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
    ---@param W Writer
    ---@param helps string[]
    ---@param notes string[]
    function RenderContext:render_footer(W, helps, notes)
        self:render_help_or_node(W, "Help", helps)
        self:render_help_or_node(W, "Note", notes)
        if #self.groups > 0 and not W.config.compact then
            local draw = W.config.char_set
            W:margin():padding(self.line_no_width + 2, draw.hbar)(draw.rbot)
                :reset "\n"
        end
    end
end

--- render the report
---@param cache Cache
---@return string
function Report:render(cache)
    local cfg = self.config
    local W = Writer.new(cfg)
    local ctx = RenderContext.new(self.id, self.pos, cache, self.labels, cfg)
    ctx:render_header(W, self.kind, self.code, self.message)
    for idx, group in ipairs(ctx.groups) do
        group:collect_multi_labels()
        group:render_reference(W, idx, ctx)
        W:empty_line(ctx.line_no_width)
        group:render_lines(W, ctx)
        if idx ~= #ctx.groups then
            W:empty_line(ctx.line_no_width)
        end
    end
    ctx:render_footer(W, self.helps, self.notes)
    return W:tostring()
end

---@class (exact) Ariadne
return {
    Cache = Cache,
    Source = Source,
    ColorGenerator = ColorGenerator,
    Characters = Characters,
    Config = Config,
    Label = Label,
    Report = Report,
}
