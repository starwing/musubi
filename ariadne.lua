---@class utf8
---@field len fun(s: string, i?: integer, j?: integer): integer?
---@field offset fun(s: string, n: integer, i?: integer): integer?, integer?
---@field width fun(s: integer|string, ambi_is_single: boolean?, fallback: integer?): integer
---@field codepoint fun(s: string, i?: integer, j?: integer, lax?: boolean): integer
local utf8 = require "lua-utf8"

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

--- @class Line
--- @field offset       integer offset of this line in the original [`Source`]
--- @field len          integer character length of this line
--- @field byte_offset  integer byte offset of this line in the original [`Source`]
--- @field byte_len     integer byte length of this line in the original [`Source`]
--- @field newline      boolean whether this line ends with a newline
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

    --- returns the character span of this line in the original [`Source`]
    ---@return integer first
    ---@return integer last
    function Line:span()
        return self.offset, self.offset + self.len - 1
    end

    --- checks if a position is within the span of this line
    ---@param pos integer
    ---@return boolean
    function Line:span_contains(pos)
        return pos >= self.offset and pos < self.offset + self.len
    end

    --- returns the byte span of this line in the original [`Source`]
    ---@return integer first
    ---@return integer last
    function Line:byte_span()
        return self.byte_offset, self.byte_offset + self.byte_len - 1
    end
end

--- @class Source : Cache
--- @field id                string
--- @field len               integer character length of the entire source
--- @field byte_len          integer byte length of the entire source
--- @field text              string the original source text
--- @field display_line_offset integer
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
        src.len = chars
        src.byte_len = bytes
        src.display_line_offset = offset or 0
        return setmetatable(src, Source)
    end

    --- implements [`Cache:fetch`]
    ---@param _ string
    ---@return Source?
    function Source:fetch(_)
        return self
    end

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
--- @field state integer[]
--- @field min_brightness number
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
--- @field cross_gap       boolean
--- @field label_attach    "start" | "end" | "middle"
--- @field compact          boolean
--- @field underlines       boolean
--- @field multiline_arrows boolean
--- @field color            Color
--- @field tab_width        integer
--- @field char_set         CharSet
--- @field index_type      "byte" | "char"
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
    function Label:with_message(msg)
        self.message = msg
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

    ---@return string
    function Writer:tostring()
        return table.concat(self)
    end
end

--- @class (exact) Report
--- @field build fun(kind: string, start_pos: integer,
---                  end_pos?: integer, source_id?: string): Report
--- @field kind string
--- @field code? string
--- @field message? string
--- @field notes string[]
--- @field help string[]
--- @field start_pos integer
--- @field end_pos? integer
--- @field source_id? string
--- @field labels Label[]
--- @field config Config
local Report = class "Report"
do
    --- creates a new Report
    ---@param kind string
    ---@param start_pos integer
    ---@param end_pos? integer
    ---@param source_id? string
    ---@return Report
    function Report.build(kind, start_pos, end_pos, source_id)
        return setmetatable({
            kind = kind,
            code = nil,
            message = nil,
            notes = {},
            help = {},
            start_pos = start_pos,
            end_pos = end_pos,
            source_id = source_id,
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
    function Report:set_message(message)
        self.message = message
        return self
    end

    ---@param note string
    ---@return Report
    function Report:add_note(note)
        self.notes[#self.notes + 1] = note
        return self
    end

    ---@param help string
    ---@return Report
    function Report:add_help(help)
        self.help[#self.help + 1] = help
        return self
    end

    ---@param label Label
    ---@return Report
    function Report:add_label(label)
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

do -- report Rendering
    ---@class LabelInfo
    ---@field multi boolean
    ---@field start_char integer
    ---@field end_char? integer
    ---@field label Label

    ---@class SourceGroup
    ---@field source_id string
    ---@field start_char integer
    ---@field end_char? integer
    ---@field labels LabelInfo[]

    --- @class LineLabel
    --- @field col integer
    --- @field info LabelInfo
    --- @field draw_msg boolean

    --- Group labels by their source
    ---@param labels Label[]
    ---@param cache Cache
    ---@param index_type "byte" | "char"
    ---@param source_id string
    ---@return SourceGroup[]
    local function get_source_groups(labels, cache, index_type, source_id)
        ---@type SourceGroup[]
        local groups = {}

        for _, label in ipairs(labels) do
            local src = assert(cache:fetch(label.source_id), "source not found")

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
                    assert(utf8.len(src.text, start_line.byte_offset, given_start - 1))
                if given_end and given_start <= given_end then
                    line_no = src:get_byte_line(given_end)
                    end_line = assert(src[line_no], "end byte offset out of range")
                    label_end_char = end_line.offset +
                        assert(utf8.len(src.text, end_line.byte_offset, given_end)) - 1
                else
                    end_line = start_line
                end
            end

            if label_start_char <= start_line.offset + start_line.len then
                --- @type LabelInfo
                local label_info = {
                    multi = start_line ~= end_line,
                    start_char = label_start_char,
                    end_char = label_end_char,
                    label = label,
                }

                local group = groups[label.source_id or source_id]
                if not group then
                    --- @type SourceGroup
                    group = {
                        source_id = label.source_id,
                        start_char = label_start_char,
                        end_char = label_end_char,
                        labels = { label_info },
                    }
                    groups[#groups + 1] = group
                    groups[label.source_id or source_id] = group
                else
                    if label_start_char < group.start_char then
                        group.start_char = label_start_char
                    end
                    if label_end_char and (not group.end_char
                            or label_end_char > group.end_char) then
                        group.end_char = label_end_char
                    end
                    group.labels[#group.labels + 1] = label_info
                end
            end
        end

        return groups
    end

    --- Render the header for a report
    ---@param W Writer
    ---@param kind string
    ---@param code string?
    ---@param message string?
    local function render_header(W, kind, code, message)
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

    --- Calculate the maximum width of line numbers in all source groups
    ---@param cache Cache
    ---@param groups SourceGroup[]
    ---@return integer
    local function calc_line_no_width(cache, groups)
        local width = 0
        for _, group in ipairs(groups) do
            local src = assert(cache:fetch(group.source_id), "source not found")
            local line_no = src:get_offset_line(group.end_char or group.start_char)
                + src.display_line_offset
            if line_no then
                local cur_width, max_line_no = 1, 1
                while cur_width * 10 <= line_no do
                    cur_width, max_line_no = cur_width + 1, max_line_no * 10
                end
                if width < cur_width then
                    width = cur_width
                end
            end
        end
        return width
    end

    --- Render the reference line for a source group
    ---@param W Writer
    ---@param report Report
    ---@param line_no_width integer
    ---@param group_idx integer
    ---@param group SourceGroup
    ---@param src Source
    local function render_reference(W, report, line_no_width, group_idx, group, src)
        local cfg = report.config
        local draw = cfg.char_set

        ---@type Line?, integer?, integer?
        local line, line_no, col_no
        if group.source_id == report.source_id then
            if cfg.index_type == "byte" then
                line_no = src:get_byte_line(report.start_pos)
                line = assert(src[line_no], "byte offset out of range")
                if line and report.start_pos <= line.byte_offset + line.byte_len - 1 then
                    col_no = assert(utf8.len(src.text, line.byte_offset,
                        report.start_pos - 1)) + 1
                else
                    line_no = nil
                end
            else
                line_no = src:get_offset_line(report.start_pos)
                line = src[line_no]
                if line then
                    col_no = report.start_pos - line.offset + 1
                end
            end
        else
            local start = group.labels[1].start_char
            line_no = src:get_offset_line(start)
            line = src[line_no]
            if line then
                col_no = start - line.offset + 1
            end
        end
        local line_str, col_str
        if not line_no then
            line_str, col_str = "?", "?"
        else
            line_str = tostring(line_no + src.display_line_offset)
            col_str = tostring(col_no)
        end
        W:padding(line_no_width + 2)
        W:margin(group_idx == 1 and draw.ltop or draw.vbar)
        W(draw.hbar)(draw.lbox):reset " "
        W(src.id) ":" (line_str) ":" (col_str) " ":margin(draw.rbox):reset "\n"
    end

    ---@param group SourceGroup
    ---@return LabelInfo[]
    ---@return LabelInfo[]
    local function collect_multi_labels(group)
        ---@type LabelInfo[]
        local multi_labels = {}
        ---@type LabelInfo[]
        local multi_labels_with_message = {}

        for _, info in ipairs(group.labels) do
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
        return multi_labels, multi_labels_with_message
    end

    --- Get the margin label for a line.
    ---
    --- Which is the most significant multiline label on this line.
    --- It's the multiline label with the minimum column (start or end),
    --- if columns are equal, the one with the maximum start position is chosen.
    ---@param line Line
    ---@param multi_labels_with_message LabelInfo[]
    ---@return LineLabel?
    local function get_margin_label(line, multi_labels_with_message)
        ---@type integer?, LabelInfo?, boolean?
        local col, info, draw_msg
        for i, cur_info in ipairs(multi_labels_with_message) do
            local cur_col, cur_draw_msg
            if line:span_contains(cur_info.start_char) then
                cur_col = cur_info.start_char - line.offset + 1
                cur_draw_msg = false
            elseif cur_info.end_char and line:span_contains(cur_info.end_char) then
                cur_col = cur_info.end_char - line.offset + 1
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
    ---@param multi_labels_with_message LabelInfo[]
    local function collect_multi_labels_in_line(line_labels, line,
                                                margin_label, multi_labels_with_message)
        for i, info in ipairs(multi_labels_with_message) do
            local col, draw_msg
            if line:span_contains(info.start_char)
                and (not margin_label or info ~= margin_label.info)
            then
                line_labels[#line_labels + 1] = {
                    col = info.start_char - line.offset + 1,
                    info = info,
                    draw_msg = false,
                }
            elseif info.end_char and line:span_contains(info.end_char) then
                line_labels[#line_labels + 1] = {
                    col = info.end_char - line.offset + 1,
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
        local end_char = line.offset + line.len
        for _, info in ipairs(group.labels) do
            if not info.multi and info.start_char >= line.offset and
                (info.end_char or info.start_char) <= end_char
            then
                local col = info.start_char
                if label_attach == "end" then
                    col = info.end_char or info.start_char
                elseif label_attach == "middle" and info.end_char then
                    col = (info.start_char + info.end_char + 1) // 2
                end
                line_labels[#line_labels + 1] = {
                    col = col - line.offset + 1,
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

    --- Check if an offset is within any of the multiline labels
    ---@param offset integer
    ---@param multi_labels LabelInfo[]
    ---@return boolean
    local function is_within_label(offset, multi_labels)
        for _, info in ipairs(multi_labels) do
            if info.start_char < offset and info.end_char > offset then
                return true
            end
        end
        return false
    end

    --- Render the line number for a specific line
    ---@param W Writer
    ---@param line_no integer?
    ---@param line_no_width integer
    ---@param is_ellipsis boolean
    ---@param cfg Config
    local function render_lineno(W, line_no, line_no_width, is_ellipsis, cfg)
        local draw = cfg.char_set
        if line_no and not is_ellipsis then
            local line_no_str = tostring(line_no)
            W " ":padding(line_no_width - #line_no_str)
            W:margin(line_no_str) " " (draw.vbar):reset()
        else
            W " ":padding(line_no_width + 1)
            if is_ellipsis then
                W:skipped_margin(draw.vbar_gap)
            else
                W:skipped_margin(draw.vbar)
            end
        end
        if not cfg.compact then
            W " "
        end
    end

    --- Render the margin arrows for a specific line
    ---@param W Writer
    ---@param is_line boolean
    ---@param is_ellipsis boolean
    ---@param line Line
    ---@param report_row? LineLabel
    ---@param report_row_is_arrow boolean
    ---@param line_labels? LineLabel[]
    ---@param margin_label? LineLabel
    ---@param multi_labels_with_message LabelInfo[]
    ---@param cfg Config
    local function render_margin(W, is_line, is_ellipsis, line,
                                 report_row, report_row_is_arrow, line_labels,
                                 margin_label, multi_labels_with_message, cfg)
        if #multi_labels_with_message == 0 then
            return
        end

        local draw = cfg.char_set
        local end_char = line.offset + line.len - 1

        ---@type LabelInfo?, LabelInfo?
        local hbar, margin_ptr
        local margin_ptr_is_start = false

        for _, info in ipairs(multi_labels_with_message) do
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

            if corner then
                local a = is_start and draw.ltop or draw.lbot
                W:use_color(corner.label.color):label(a):compact(draw.hbar)
            elseif vbar and hbar and not cfg.cross_gap then
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
                W:reset(cfg.compact and ' ' or '  ')
            end
        end
        if hbar then
            W:use_color(hbar.label.color):label(draw.hbar):compact(draw.hbar):reset()
        elseif margin_ptr and is_line then
            W:use_color(margin_ptr.label.color):label(draw.rarrow):compact ' ':reset()
        else
            W:reset(cfg.compact and ' ' or '  ')
        end
    end

    --- Get the highest priority highlight for a offset
    ---@param offset integer
    ---@param margin_label? LineLabel
    ---@param multi_labels LabelInfo[]
    ---@param line_labels LineLabel[]
    ---@return LabelInfo?
    local function get_highlight(offset, margin_label, multi_labels, line_labels)
        local result

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

        if margin_label then
            update_result(margin_label.info)
        end
        for _, info in ipairs(multi_labels) do
            update_result(info)
        end
        for _, ll in ipairs(line_labels) do
            if ll.info.end_char then
                update_result(ll.info)
            end
        end
        return result
    end

    --- Find the character that should be drawn and the number of times it
    --- should be drawn for each char
    --- @param s string
    --- @param byte_offset integer
    --- @param col integer
    --- @param cfg Config
    --- @return integer repeat_count
    --- @return integer codepoint
    local function char_width(s, byte_offset, col, cfg)
        local c = utf8.codepoint(s, utf8.offset(s, col, byte_offset))
        if c == 9 then -- tab
            return cfg.tab_width - ((col - 1) % cfg.tab_width), 32
        elseif c == 32 then
            return 1, 32
        else
            return utf8.width(c), c
        end
    end

    --- Render a line with highlights
    ---@param W Writer
    ---@param line Line
    ---@param margin_label LineLabel?
    ---@param line_labels LineLabel[]
    ---@param multi_labels LineLabel[]
    ---@param src Source
    ---@param cfg Config
    local function render_line(W, line, margin_label, line_labels, multi_labels, src, cfg)
        --- @type Color?
        local cur_color
        local cur_offset, cur_byte_offset = 1, line.byte_offset
        for i = 1, line.len do
            local highlight = get_highlight(
                line.offset + i - 1,
                margin_label,
                multi_labels,
                line_labels
            )
            local next_color = highlight and highlight.label.color
            local repeat_count, cp = char_width(src.text, line.byte_offset, i, cfg)
            if cur_color ~= next_color or (cp == 32 and repeat_count > 1) then
                local next_start_bytes = assert(utf8.offset(
                    src.text, i - cur_offset + 1, cur_byte_offset))
                if i > cur_offset then
                    W:label_or_unimportant(cur_color, (src.text:sub(
                        cur_byte_offset, next_start_bytes - 1
                    ):gsub("\t", ""))):reset()
                end
                if cp == 32 and repeat_count > 1 then
                    W:label_or_unimportant(next_color, (" "):rep(repeat_count))
                end
                cur_color = next_color
                cur_offset = i
                cur_byte_offset = next_start_bytes
            end
        end
        W:label_or_unimportant(cur_color, (src.text:sub(
            cur_byte_offset, line.byte_offset + line.byte_len - 1
        ):gsub("\t", ""))):reset()
    end

    --- Should we draw a vertical bar as part of a label arrow on this line?
    ---@param col integer
    ---@param row integer
    ---@param margin_label LineLabel?
    ---@param line_labels LineLabel[]
    ---@return LineLabel?
    local function get_vbar(col, row, margin_label, line_labels)
        for i, ll in ipairs(line_labels) do
            if ll.info.label.message and
                (not margin_label or margin_label.info ~= ll.info)
            then
                if ll.col == col and row <= i then
                    return ll
                end
            end
        end
    end

    --- Should we draw an underline as part of a label arrow on this line?
    ---@param col integer
    ---@param line_labels LineLabel[]
    ---@param line Line
    ---@param cfg Config
    ---@return LineLabel?
    local function get_underline(col, line_labels, line, cfg)
        if not cfg.underlines then
            return nil
        end
        local offset = line.offset + col - 1
        ---@type LineLabel?
        local result
        for i, ll in ipairs(line_labels) do
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

    --- Calculate the maximum arrow line length for a specific line
    ---@param line Line
    ---@param line_labels LineLabel[]
    ---@param compact boolean
    ---@return integer
    local function calc_arrow_len(line, line_labels, compact)
        local arrow_end_space = compact and 1 or 2
        local arrow_len = 0
        for l, ll in ipairs(line_labels) do
            if ll.info.multi then
                arrow_len = line.len + (line.newline and 1 or 0)
            else
                local cur = (ll.info.end_char or ll.info.start_char - 1) - line.offset + 1
                if arrow_len < cur then
                    arrow_len = cur
                end
            end
        end
        return arrow_len + arrow_end_space
    end

    --- Render arrows for a line
    ---@param W Writer
    ---@param line_no_width integer
    ---@param line Line
    ---@param is_ellipsis boolean
    ---@param line_labels LineLabel[]
    ---@param margin_label LineLabel?
    ---@param multi_labels_with_message LineLabel[]
    ---@param src Source
    ---@param cfg Config
    local function render_arrows(W, line_no_width, line, is_ellipsis,
                                 line_labels, margin_label,
                                 multi_labels_with_message, src, cfg)
        local draw = cfg.char_set

        -- Determine label bounds so we know where to put error messages
        local arrow_len = calc_arrow_len(line, line_labels, cfg.compact)

        -- Arrows
        for row, ll in ipairs(line_labels) do
            -- No message to draw thus no arrow to draw
            if ll.info.label.message then
                if not cfg.compact then
                    -- Margin alternate
                    render_lineno(W, nil, line_no_width, is_ellipsis, cfg)
                    render_margin(W, false, is_ellipsis, line, ll, false, line_labels,
                        margin_label, multi_labels_with_message, cfg)
                    for col = 1, arrow_len do
                        local width = 1
                        if col <= line.len then
                            width = char_width(src.text, line.byte_offset, col, cfg)
                        end
                        local vbar = get_vbar(col, row, margin_label, line_labels)
                        local underline
                        if row == 1 then
                            underline = get_underline(col, line_labels, line, cfg)
                        end
                        if vbar and underline then
                            -- temporaroyly disable features here
                            local vbar_len = vbar.info.end_char
                                and (vbar.info.end_char - vbar.info.start_char + 1)
                                or 0
                            local a = draw.underbar
                            if vbar_len <= 1 or true then
                                a = draw.underbar
                            elseif line.offset + col - 1 == vbar.info.start_char then
                                a = draw.ltop
                            elseif line.offset + col - 1 == vbar.info.end_char then
                                a = draw.rtop
                            end
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
                render_lineno(W, nil, line_no_width, is_ellipsis, cfg)
                render_margin(W, false, is_ellipsis, line, ll, true, line_labels,
                    margin_label, multi_labels_with_message, cfg)

                -- Lines
                for col = 1, arrow_len do
                    local width = 1
                    if col <= line.len then
                        width = char_width(src.text, line.byte_offset, col, cfg)
                    end
                    local is_hbar = (col > ll.col) ~= ll.info.multi or
                        ll.draw_msg and col > ll.col
                    local vbar = get_vbar(col, row, margin_label, line_labels)
                    if col == ll.col and (not margin_label or margin_label.info ~= ll.info) then
                        local a = draw.rbot
                        if not ll.info.multi then
                            a = draw.lbot
                        elseif ll.draw_msg then
                            a = draw.mbot
                        end
                        W:use_color(ll.info.label.color):label(a):padding(width - 1, draw.hbar)
                    elseif vbar and col ~= ll.col then
                        local a, b = draw.vbar, ' '
                        if not cfg.cross_gap and is_hbar then
                            a = draw.xbar
                        elseif is_hbar then
                            a, b = draw.hbar, draw.hbar
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

    --- Render notes or help items
    ---@param W Writer
    ---@param prefix string
    ---@param items string[]
    ---@param line_no_width integer
    ---@param cfg Config
    local function render_help_or_node(W, prefix, items, line_no_width, cfg)
        for i, item in ipairs(items) do
            if not cfg.compact then
                render_lineno(W, nil, line_no_width, false, cfg)
                W "\n"
            end
            local item_prefix = #items > 1 and ("%s %d"):format(prefix, i) or prefix
            local item_prefix_len
            for line in item:gmatch "([^\n]*)\n?" do
                render_lineno(W, nil, line_no_width, false, cfg)
                if not item_prefix_len then
                    W:note(item_prefix) ": " (line) "\n"
                    item_prefix_len = #item_prefix + 2
                else
                    W:padding(item_prefix_len)(line) "\n"
                end
            end
        end
    end

    --- render the report
    ---@param cache Cache | Source
    ---@return string
    function Report:render(cache)
        local cfg = self.config
        local draw = cfg.char_set
        local groups = get_source_groups(self.labels, cache, cfg.index_type,
            self.source_id or "<unknown>")
        local W = Writer.new(cfg)

        render_header(W, self.kind, self.code, self.message)

        -- line number maximum width
        local line_no_width = calc_line_no_width(cache, groups)

        -- source sections
        for group_idx, group in ipairs(groups) do
            local src = assert(cache:fetch(group.source_id), "source not found")

            -- Render reference line
            render_reference(W, self, line_no_width, group_idx, group, src)
            if not cfg.compact then
                W:padding(line_no_width + 2):margin(draw.vbar):reset "\n"
            end

            -- Generate lists of multiline labels
            local multi_labels, multi_labels_with_message =
                collect_multi_labels(group)

            local is_ellipsis = false
            local line_start = src:get_offset_line(group.start_char)
            local line_end = line_start
            if group.end_char then
                line_end = src:get_offset_line(group.end_char)
            end
            for idx = line_start, line_end do
                local line = assert(src[idx], "group line out of range")
                local margin_label = get_margin_label(line, multi_labels_with_message)

                -- Generate a list of labels for this line, along with their label columns
                ---@type LineLabel[]
                local line_labels = {}
                collect_multi_labels_in_line(line_labels, line, margin_label,
                    multi_labels_with_message)
                collect_labels_in_line(line_labels, line, group, cfg.label_attach)
                sort_line_labels(line_labels)

                local draw_line = false
                if #line_labels > 0 or margin_label then
                    is_ellipsis, draw_line = false, true
                elseif not is_ellipsis and is_within_label(line.offset, multi_labels) then
                    is_ellipsis, draw_line = true, true
                else
                    -- Skip this line if we don't have labels for it
                    if not self.config.compact and not is_ellipsis then
                        render_lineno(W, nil, line_no_width, is_ellipsis, cfg)
                        W "\n"
                    end
                    is_ellipsis, draw_line = true, false
                end
                if draw_line then
                    render_lineno(W, idx + src.display_line_offset,
                        line_no_width, is_ellipsis, cfg)
                    render_margin(W, true, is_ellipsis, line, nil, false, nil,
                        margin_label, multi_labels_with_message, cfg)
                    if not is_ellipsis then
                        render_line(W, line, margin_label, line_labels,
                            multi_labels, src, cfg)
                    end
                    W "\n"

                    render_arrows(W, line_no_width, line, is_ellipsis,
                        line_labels, margin_label, multi_labels_with_message,
                        src, cfg)
                end
            end

            -- Tail of report
            if not self.config.compact and group_idx < #groups then
                W:padding(line_no_width + 2):margin(draw.vbar):reset "\n"
            end
        end

        render_help_or_node(W, "Help", self.help, line_no_width, self.config)
        render_help_or_node(W, "Note", self.notes, line_no_width, self.config)
        if #groups > 0 and not self.config.compact then
            W:margin():padding(line_no_width + 2, draw.hbar)(draw.rbot):reset "\n"
        end
        return W:tostring()
    end
end

---@class (exact) Ariadne
return {
    Source = Source,
    ColorGenerator = ColorGenerator,
    Characters = Characters,
    Config = Config,
    Label = Label,
    Report = Report,
}
