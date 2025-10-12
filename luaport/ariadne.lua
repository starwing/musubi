local ariadne = {}

--[[
Utility helpers
]]

local utf8 = utf8

-- copy_table creates a shallow copy so builder structs can isolate their mutable state.
local function copy_table(source)
	local target = {}
	for key, value in pairs(source) do
		target[key] = value
	end
	return target
end

-- repeat_char mirrors string.rep but guards against negative counts.
local function repeat_char(ch, count)
	if count <= 0 then
		return ""
	end
	return string.rep(ch, count)
end

-- digits counts base-10 digits used when printing line numbers.
local function digits(value)
	local n = 0
	repeat
		n = n + 1
		value = value // 10
	until value == 0
	return n
end

-- safe_utf8_len returns a character length and gracefully falls back to bytes.
local function safe_utf8_len(text)
	return utf8.len(text) or #text
end

-- substring_byte_length wraps the byte length lookup to keep naming intent explicit.
local function substring_byte_length(text)
	return #text
end

-- trim_end removes trailing whitespace and returns a single string value.
local function trim_end(text)
	local trimmed = text:gsub("%s+$", "")
	return trimmed
end

local function rtrim(text)
	return trim_end(text)
end

local function split_lines(text)
	local lines = {}
	if text == nil or text == "" then
		lines[1] = ""
		return lines
	end
	for line in (text .. "\n"):gmatch("(.-)\n") do
		lines[#lines + 1] = line
	end
	if #lines == 0 then
		lines[1] = ""
	end
	return lines
end

-- min_value keeps track of the running minimum while tolerating nil sentinels.
local function min_value(current, value)
	if current == nil or value < current then
		return value
	end
	return current
end

-- max_value keeps track of the running maximum while tolerating nil sentinels.
local function max_value(current, value)
	if current == nil or value > current then
		return value
	end
	return current
end

--[[
Enumerations / constants
]]

local LABEL_ATTACH = {
	start = "start",
	middle = "middle",
	end_ = "end",
}

local INDEX_TYPE = {
	byte = "byte",
	char = "char",
}

local CHAR_SET = {
	unicode = "unicode",
	ascii = "ascii",
}

local REPORT_KINDS = {
	error = "Error",
	warning = "Warning",
	advice = "Advice",
	custom = function(text)
		return text
	end,
}

--[[
Config implementation
]]

-- Config holds rendering options and uses a metatable so methods coexist with stored values.
local Config = {}

local Config_meta = {}

-- The __index metamethod returns either a method or the stored option value.
function Config_meta.__index(self, key)
	local method = Config[key]
	if method ~= nil then
		return method
	end
	return self._values[key]
end

-- The __newindex metamethod writes option values into the backing store.
function Config_meta.__newindex(self, key, value)
	self._values[key] = value
end

local DEFAULT_CONFIG = {
	cross_gap = true,
	label_attach = LABEL_ATTACH.middle,
	compact = false,
	underlines = true,
	multiline_arrows = true,
	color = true,
	tab_width = 4,
	char_set = CHAR_SET.unicode,
	index_type = INDEX_TYPE.char,
}

local function ensure_attach(value)
	if value == "start" or value == "middle" or value == "end" then
		return value
	end
	error("label_attach must be start, middle, or end", 2)
end

local function ensure_char_set(value)
	if value == "unicode" or value == "ascii" then
		return value
	end
	error("char_set must be unicode or ascii", 2)
end

local function ensure_index_type(value)
	if value == "byte" or value == "char" then
		return value
	end
	error("index_type must be byte or char", 2)
end

-- make_config builds a config instance seeded from defaults or an existing snapshot.
local function make_config(base)
	return setmetatable({ _values = copy_table(base or DEFAULT_CONFIG) }, Config_meta)
end

-- cross_gap toggles whether arrow lines bridge gaps in multiline diagnostics.
function Config:cross_gap(value)
	self._values.cross_gap = not not value
	return self
end

-- label_attach selects the label anchor position (start/middle/end of the span).
function Config:label_attach(value)
	self._values.label_attach = ensure_attach(value)
	return self
end

-- compact switches to a condensed rendering without blank spacer lines.
function Config:compact(value)
	self._values.compact = not not value
	return self
end

-- underlines enables inline underline guides for single-line labels.
function Config:underlines(value)
	self._values.underlines = not not value
	return self
end

-- multiline_arrows controls whether multi-line spans draw arrow heads.
function Config:multiline_arrows(value)
	self._values.multiline_arrows = not not value
	return self
end

-- color toggles ANSI styling (the color palette is stubbed in this port).
function Config:color(value)
	self._values.color = not not value
	return self
end

-- tab_width tweaks how hard tabs expand when rendering source lines.
function Config:tab_width(value)
	if value < 1 then
		error("tab_width must be >= 1", 2)
	end
	self._values.tab_width = value
	return self
end

-- char_set picks the ASCII or Unicode drawing characters.
function Config:char_set(value)
	self._values.char_set = ensure_char_set(value)
	return self
end

-- index_type chooses whether spans are expressed in bytes or characters.
function Config:index_type(value)
	self._values.index_type = ensure_index_type(value)
	return self
end

-- clone returns a detached config copy so further mutations do not leak.
function Config:clone()
	return make_config(self._values)
end

-- get_option exposes the stored option value by key for internal lookups.
function Config:get_option(key)
	return self._values[key]
end

-- char_width converts a raw source character into the glyph and width we should render.
function Config:char_width(ch, column)
	if ch == "\t" then
		local tab_width = self._values.tab_width
		local tab_end = ((column // tab_width) + 1) * tab_width
		return " ", tab_end - column
	end
	if ch:match("%s") then
		return " ", 1
	end
	return ch, 1
end

--[[
Source representation
]]

local Source = {}
Source.__index = Source

-- compute_lines tokenises the original text into line records with byte/char metadata.
local function compute_lines(text)
	if text == "" then
		return {
			{
				offset = 0,
				char_len = 0,
				byte_offset = 0,
				byte_len = 0,
				text = "",
			},
		}
	end

	local lines = {}
	local total_chars = 0
	local total_bytes = 0
	local start_byte = 1
	local length = #text

	while start_byte <= length do
		local newline_pos = text:find("\n", start_byte, true)
		local end_byte
		if newline_pos then
			end_byte = newline_pos
		else
			end_byte = length
		end

		local line_text = text:sub(start_byte, end_byte)
		local char_len = safe_utf8_len(line_text)
		local byte_len = substring_byte_length(line_text)

		lines[#lines + 1] = {
			offset = total_chars,
			char_len = char_len,
			byte_offset = total_bytes,
			byte_len = byte_len,
			text = line_text,
		}

		total_chars = total_chars + char_len
		total_bytes = total_bytes + byte_len

		if newline_pos then
			start_byte = newline_pos + 1
		else
			break
		end
	end

	return lines
end

local function new_source(text)
	local lines = compute_lines(text)
	local total_characters = 0
	local total_bytes = 0
	if #lines > 0 then
		local last = lines[#lines]
		total_characters = last.offset + last.char_len
		total_bytes = last.byte_offset + last.byte_len
	end

	return setmetatable({
		text = text,
		lines = lines,
		char_len = total_characters,
		byte_len = total_bytes,
		display_line_offset = 0,
	}, Source)
end

	-- with_display_line_offset enables external callers to shift the printed line numbers.
function Source:with_display_line_offset(offset)
	self.display_line_offset = offset
	return self
end

	-- line retrieves the raw line record at a zero-based index.
function Source:line(index)
	return self.lines[index + 1]
end

	-- get_line_text unwraps the line struct to expose the stored text.
function Source:get_line_text(line)
	local _ = self
	return line.text
end

	-- binary_search locates the greatest line index whose key is <= target.
local function binary_search(lines, target, key)
	local low = 1
	local high = #lines
	while low <= high do
		local mid = (low + high) // 2
		if target < lines[mid][key] then
			high = mid - 1
		else
			low = mid + 1
		end
	end
	if high < 1 then
		high = 1
	elseif high > #lines then
		high = #lines
	end
	return high - 1
end

-- line_index_for_offset finds the line containing the char offset (0-based).
function Source:line_index_for_offset(offset)
	if offset <= 0 then
		return 0
	end
	return binary_search(self.lines, offset, "offset")
end

-- line_index_for_byte finds the line containing the byte offset (0-based).
function Source:line_index_for_byte(byte_offset)
	if byte_offset <= 0 then
		return 0
	end
	return binary_search(self.lines, byte_offset, "byte_offset")
end

-- get_offset_line returns the line record, index, and relative char column for a char offset.
function Source:get_offset_line(offset)
	if offset > self.char_len then
		return nil
	end
	local idx = self:line_index_for_offset(offset)
	local line = self.lines[idx + 1]
	if not line then
		return nil
	end
	return line, idx, offset - line.offset
end

-- char_count_for_prefix converts a byte prefix into a character length.
local function char_count_for_prefix(text, byte_count)
	if byte_count <= 0 then
		return 0
	end
	local prefix = text:sub(1, byte_count)
	return safe_utf8_len(prefix)
end

-- split_at_column divides text into the prefix and suffix around the given char column.
local function split_at_column(text, column)
	if column <= 0 then
		return "", text
	end
	local byte_index = utf8.offset(text, column + 1)
	if not byte_index then
		return text, ""
	end
	return text:sub(1, byte_index - 1), text:sub(byte_index)
end

-- get_byte_line returns the line record, index, and relative byte column for a byte offset.
function Source:get_byte_line(byte_offset)
	if byte_offset > self.byte_len then
		return nil
	end
	local idx = self:line_index_for_byte(byte_offset)
	local line = self.lines[idx + 1]
	if not line then
		return nil
	end
	return line, idx, byte_offset - line.byte_offset
end

-- get_line_range converts an overall span into the first/last line indexes we must print.
function Source:get_line_range(span)
	local start_offset = span.start
	local finish_offset = span.finish
	if finish_offset < start_offset then
		finish_offset = start_offset
	end

	local start_line = self:line_index_for_offset(start_offset)
	local end_lookup = math.max(finish_offset - 1, start_offset)
	local end_line = self:line_index_for_offset(end_lookup) + 1

	return { start = start_line, finish = end_line }
end

--[[
Span helpers
]]

-- make_span normalises the provided start/finish positions into a table.
local function make_span(start_pos, finish_pos)
	if start_pos > finish_pos then
		error("span start must be <= end", 2)
	end
	return {
		start = start_pos,
		finish = finish_pos,
	}
end

-- span_length returns the non-negative length of the span.
local function span_length(span)
	return math.max(span.finish - span.start, 0)
end

-- span_last_offset gives the greatest in-range offset for inclusive comparisons.
local function span_last_offset(span)
	if span.finish <= span.start then
		return span.start
	end
	return span.finish - 1
end

--[[
Label implementation
]]

local Label = {}
Label.__index = Label

local DEFAULT_LABEL_DISPLAY = {
	message = nil,
	color = nil,
	order = 0,
	priority = 0,
}

local function new_label(start_pos, finish_pos)
	return setmetatable({
		span = make_span(start_pos, finish_pos),
		display = copy_table(DEFAULT_LABEL_DISPLAY),
	}, Label)
end

function Label:message(text)
	self.display.message = text
	return self
end

function Label:color(value)
	self.display.color = value
	return self
end

function Label:order(value)
	self.display.order = value
	return self
end

function Label:priority(value)
	self.display.priority = value
	return self
end

--[[
Report builder and report objects
]]

local ReportBuilder = {}
ReportBuilder.__index = ReportBuilder

local function new_report(kind, span_obj)
	return setmetatable({
		_state = {
			kind = kind,
			code = nil,
			message = nil,
			notes = {},
			helps = {},
			span = span_obj,
			labels = {},
			config = make_config(),
		},
	}, ReportBuilder)
end

function ReportBuilder:config(cfg)
	self._state.config = cfg:clone()
	return self
end

function ReportBuilder:message(text)
	self._state.message = text
	return self
end

function ReportBuilder:code(value)
	self._state.code = value
	return self
end


function ReportBuilder:label(label_obj)
	local labels = self._state.labels
	labels[#labels + 1] = label_obj
	return self
end

function ReportBuilder:help(text)
	local helps = self._state.helps
	helps[#helps + 1] = text
	return self
end

function ReportBuilder:note(text)
	local notes = self._state.notes
	notes[#notes + 1] = text
	return self
end

function ReportBuilder:finish()
	local state = self._state
	local report = {
		kind = state.kind,
		code = state.code,
		message = state.message,
		notes = state.notes,
		helps = state.helps,
		span = state.span,
		labels = state.labels,
		config = state.config,
	}

	local Report = {}
	Report.__index = Report

	function Report.write_to_string(report_instance, source)
		return ariadne.render(report_instance, source)
	end

	return setmetatable(report, Report)
end

--[[
Characters (draw set)
]]

local CHARACTERS = {
	unicode = {
		hbar = "─",
		vbar = "│",
		xbar = "┼",
		vbar_break = "┆",
		vbar_gap = "┆",
		uarrow = "▲",
		rarrow = "▶",
		ltop = "╭",
		mtop = "┬",
		rtop = "╮",
		lbot = "╰",
		rbot = "╯",
		mbot = "┴",
		lbox = "[",
		rbox = "]",
		lcross = "├",
		rcross = "┤",
		underbar = "┬",
		underline = "─",
	},
	ascii = {
		hbar = "-",
		vbar = "|",
		xbar = "+",
		vbar_break = "*",
		vbar_gap = ":",
		uarrow = "^",
		rarrow = ">",
		ltop = ",",
		mtop = "v",
		rtop = ".",
		lbot = "`",
		rbot = "'",
		mbot = "^",
		lbox = "[",
		rbox = "]",
		lcross = "|",
		rcross = "|",
		underbar = "|",
		underline = "^",
	},
}

function ariadne.characters()
	return CHARACTERS
end

--[[
Label grouping helpers
]]

local function index_to_char_offset(source, config, offset)
	if config:get_option("index_type") == INDEX_TYPE.char then
		return offset
	end
	local line, _, byte_column = source:get_byte_line(offset)
	if not line then
		return offset
	end
	local chars_before = char_count_for_prefix(line.text, byte_column)
	return line.offset + chars_before
end

-- index_range_to_char_span maps the incoming span into character offsets for rendering.
local function index_range_to_char_span(source, config, span)
	if config:get_option("index_type") == INDEX_TYPE.char then
		local start_line, start_idx = source:get_offset_line(span.start)
		if not start_line then
			return nil
		end
		local char_span_start = span.start

		local end_line
		local char_span_end
		if span.start >= span.finish then
			end_line = start_idx
			char_span_end = char_span_start
		else
			local lookup = span.finish - 1
			local _, end_idx = source:get_offset_line(lookup)
			if not end_idx then
				return nil
			end
			end_line = end_idx
			char_span_end = span.finish
		end

		return {
			start = char_span_start,
			finish = char_span_end,
			start_line = start_idx,
			end_line = end_line,
		}
	end

	local start_line, start_idx, start_byte_col = source:get_byte_line(span.start)
	if not start_line then
		return nil
	end
	local start_chars = char_count_for_prefix(start_line.text, start_byte_col)
	local char_start = start_line.offset + start_chars

	local char_end
	local end_line_idx
	if span.start >= span.finish then
		char_end = char_start
		end_line_idx = start_idx
	else
		local end_pos = span.finish - 1
		local end_line, end_idx, end_byte_col = source:get_byte_line(end_pos)
		if not end_line then
			return nil
		end
		local chars_until_end = char_count_for_prefix(end_line.text, end_byte_col + 1)
		char_end = end_line.offset + chars_until_end
		end_line_idx = end_idx
	end

	return {
		start = char_start,
		finish = char_end,
		start_line = start_idx,
		end_line = end_line_idx,
	}
end

-- make_label_info decorates a label with computed span metadata for rendering.
local function make_label_info(label, char_span)
	local kind
	if char_span.start_line == char_span.end_line then
		kind = "inline"
	else
		kind = "multiline"
	end
	return {
		kind = kind,
		char_span = make_span(char_span.start, char_span.finish),
		display = label.display,
		start_line = char_span.start_line,
		end_line = char_span.end_line,
	}
end

-- label_last_offset proxies span_last_offset for readability downstream.
local function label_last_offset(info)
	return span_last_offset(info.char_span)
end

-- compute_source_groups collates labels per source so we can render each section once.
local function compute_source_groups(report, source)
	local groups = {}
	if #report.labels == 0 then
		return groups
	end

	local group = {
		source = source,
		char_span = { start = nil, finish = nil },
		labels = {},
	}

	for _, label in ipairs(report.labels) do
		local char_span = index_range_to_char_span(source, report.config, label.span)
		if char_span then
			group.char_span.start = min_value(group.char_span.start, char_span.start)
			group.char_span.finish = max_value(group.char_span.finish, char_span.finish)
			group.labels[#group.labels + 1] = make_label_info(label, char_span)
		end
	end

	if group.char_span.start == nil then
		return {}
	end

	groups[#groups + 1] = group
	return groups
end

--[[
Rendering helpers
]]

-- format_kind normalises the human-readable error kind.
local function format_kind(kind)
	local lower = kind:lower()
	if REPORT_KINDS[lower] then
		local value = REPORT_KINDS[lower]
		if type(value) == "function" then
			return value(kind)
		end
		return value
	end
	return REPORT_KINDS.custom(kind)
end

-- format_code adds surrounding brackets when a report code is present.
local function format_code(code)
	if not code then
		return ""
	end
	return string.format("[%s] ", code)
end

-- make_location formats the span start into user-facing line/column strings.
local function make_location(source, config, span)
	local offset = span.start
	local reference = index_to_char_offset(source, config, offset)
	local line, idx, column = source:get_offset_line(reference)
	if not line then
		return {
			line = "?",
			column = "?",
		}
	end
	return {
		line = tostring((idx or 0) + 1 + source.display_line_offset),
		column = tostring((column or 0) + 1),
	}
end

-- string_builder returns an append buffer and function to collect its contents.
local function string_builder()
	local buffer = {}
	return buffer, function()
		return table.concat(buffer)
	end
end

-- draw_margin emits the gutter prefix for a given line or spacer.
local function draw_margin(builder, draw, config, line_no_width, opts)
	local margin_char = draw.vbar

	local fragments = {}

	if opts.is_line and not opts.is_ellipsis then
		local line_no = tostring(opts.line_index + 1)
		local padding = repeat_char(" ", line_no_width - #line_no)
		fragments[#fragments + 1] = " "
		fragments[#fragments + 1] = padding
		fragments[#fragments + 1] = line_no
		fragments[#fragments + 1] = " "
		fragments[#fragments + 1] = margin_char
	else
		fragments[#fragments + 1] = " "
		fragments[#fragments + 1] = repeat_char(" ", line_no_width + 1)
		fragments[#fragments + 1] = opts.is_ellipsis and draw.vbar_gap or draw.vbar
	end

	if not config:get_option("compact") then
		fragments[#fragments + 1] = " "
	end

	builder[#builder + 1] = table.concat(fragments)
end

-- render_report assembles the formatted diagnostic into a single string buffer by walking
-- each source group, drawing the margin, inline highlights, arrow lines, and trailing
-- help/note sections. It mirrors the Rust formatter closely so we can diff behaviour.
local function render_report(report, source)
	local config = report.config
	local draw = CHARACTERS[config:get_option("char_set")]

	local groups = compute_source_groups(report, source)

	local buffer, result = string_builder()

	buffer[#buffer + 1] = string.format("%s%s: %s\n", format_code(report.code), format_kind(report.kind), report.message or "")

	if #groups == 0 then
		return result()
	end

	local line_no_width = 0
	for _, group in ipairs(groups) do
		local range = source:get_line_range(group.char_span)
		group.line_range = range
		group.source_name = "<unknown>"
		group.primary_location = make_location(source, config, report.span)
		line_no_width = math.max(line_no_width, digits(range.finish))
	end

	for group_index, group in ipairs(groups) do
		local range = group.line_range
		local prefix = repeat_char(" ", line_no_width + 2)
		local box_open = group_index == 1 and draw.ltop or draw.lcross
		buffer[#buffer + 1] = string.format("%s%s%s%s %s %s\n", prefix, box_open, draw.hbar, draw.lbox, string.format("%s:%s:%s", group.source_name, group.primary_location.line, group.primary_location.column), draw.rbox)

		if not config:get_option("compact") then
			buffer[#buffer + 1] = string.format("%s%s\n", prefix, draw.vbar)
		end

		local multi_labels = {}
		local multi_with_message = {}

		for _, label in ipairs(group.labels) do
			if label.kind == "multiline" then
				multi_labels[#multi_labels + 1] = label
				if label.display.message then
					multi_with_message[#multi_with_message + 1] = label
				end
			end
		end

		table.sort(multi_labels, function(a, b)
			return span_length(a.char_span) > span_length(b.char_span)
		end)

		table.sort(multi_with_message, function(a, b)
			return span_length(a.char_span) > span_length(b.char_span)
		end)

		local is_ellipsis = false

		for line_index = range.start, range.finish - 1 do
			local line = source:line(line_index)
			if not line then
				goto continue_line
			end

			local line_text = trim_end(source:get_line_text(line))

			local line_labels = {}

			for _, label in ipairs(group.labels) do
				if label.kind == "inline" and line_index == label.start_line then
					local attach
					if config:get_option("label_attach") == LABEL_ATTACH.start then
						attach = label.char_span.start
					elseif config:get_option("label_attach") == LABEL_ATTACH.end_ then
						attach = label_last_offset(label)
					else
						attach = (label.char_span.start + label.char_span.finish) // 2
					end
					line_labels[#line_labels + 1] = {
						col = attach - line.offset,
						label = label,
						multi = false,
						draw_message = true,
					}
				end
			end

			for _, label in ipairs(multi_with_message) do
				local is_start = line_index == label.start_line
				local is_end = line_index == label.end_line
				if is_start or is_end then
					local col
					if is_start then
						col = label.char_span.start - line.offset
					else
						col = math.max(label.char_span.start - line.offset, 0)
					end
					line_labels[#line_labels + 1] = {
						col = col,
						label = label,
						multi = true,
						draw_message = is_end,
					}
				end
			end

			if #line_labels == 0 then
				local within_multiline = false
				for _, label in ipairs(multi_labels) do
					if line_index > label.start_line and line_index < label.end_line then
						within_multiline = true
						break
					end
				end
				if within_multiline then
					draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = false, is_ellipsis = true })
					buffer[#buffer + 1] = ":\n"
					is_ellipsis = true
					goto continue_line
				end
				if not config:get_option("compact") and not is_ellipsis then
					draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = false, is_ellipsis = false })
					buffer[#buffer + 1] = "\n"
				end
				is_ellipsis = true
				goto continue_line
			end

			is_ellipsis = false

			table.sort(line_labels, function(a, b)
				if a.label.display.order ~= b.label.display.order then
					return a.label.display.order < b.label.display.order
				end
				if a.col ~= b.col then
					return a.col < b.col
				end
				return span_length(a.label.char_span) < span_length(b.label.char_span)
			end)

			local pointer_data
			for _, ll in ipairs(line_labels) do
				if ll.multi then
					local col = math.max(ll.col, 0)
					pointer_data = {
						col = col,
						arrow = (ll.draw_message and draw.vbar or draw.ltop) .. draw.hbar .. draw.rarrow .. " ",
					}
					break
				end
			end

			draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = true, is_ellipsis = false })

			local text_row = line_text
			if pointer_data then
				local col = pointer_data.col
				local text_prefix, suffix = split_at_column(line_text, col)
				local prefix_len = safe_utf8_len(text_prefix)
				if prefix_len < col then
					text_prefix = text_prefix .. repeat_char(" ", col - prefix_len)
				end
				text_row = text_prefix .. pointer_data.arrow .. suffix
			end

			buffer[#buffer + 1] = text_row .. "\n"
			local rendered_line_width = safe_utf8_len(text_row)
			local arrow_labels = {}
			for _, line_label in ipairs(line_labels) do
				if line_label.label.display.message and (not line_label.multi or line_label.draw_message) then
					arrow_labels[#arrow_labels + 1] = line_label
				end
			end

			local highlight_cells = {}
			local highlight_meta = {}
			local function better_highlight(existing, candidate)
				if not existing then
					return true
				end
				if candidate.priority ~= existing.priority then
					return candidate.priority > existing.priority
				end
				return candidate.span_len < existing.span_len
			end

			for _, line_label in ipairs(line_labels) do
				local display = line_label.label.display
				if not display.message then
					goto continue_label_highlight
				end
				if line_label.multi then
					goto continue_label_highlight
				end
				local span_start = math.max(line_label.label.char_span.start, line.offset)
				local span_finish = math.min(line_label.label.char_span.finish, line.offset + line.char_len)
				local start_col = math.max(span_start - line.offset, 0)
				local end_col = math.max(span_finish - line.offset, start_col)
				local candidate = {
					priority = display.priority or 0,
					span_len = span_length(line_label.label.char_span),
					label = line_label.label,
				}
				for col = start_col, end_col - 1 do
					if col >= 0 then
						if better_highlight(highlight_meta[col], candidate) then
							highlight_cells[col] = draw.underline
							highlight_meta[col] = copy_table(candidate)
						end
					end
				end
				local attach_col = line_label.col
				if attach_col >= 0 and attach_col < line.char_len then
					local attach_candidate = candidate
					attach_candidate.span_len = 0
					if better_highlight(highlight_meta[attach_col], attach_candidate) then
						highlight_cells[attach_col] = draw.underbar
						highlight_meta[attach_col] = attach_candidate
					end
				end
				::continue_label_highlight::
			end

			local has_highlight = false
			local highlight_chars = {}
			for col = 0, line.char_len - 1 do
				local ch = highlight_cells[col] or " "
				highlight_chars[#highlight_chars + 1] = ch
				if ch ~= " " then
					has_highlight = true
				end
			end
			if has_highlight then
				draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = false, is_ellipsis = false })
				buffer[#buffer + 1] = table.concat(highlight_chars) .. "\n"
			end

			local arrow_end_space = config:get_option("compact") and 1 or 2
			local arrow_span_width = 0
			for _, ll in ipairs(line_labels) do
				if ll.multi then
					arrow_span_width = math.max(arrow_span_width, line.char_len)
				else
					local span_end = math.max(ll.label.char_span.finish - line.offset, 0)
					arrow_span_width = math.max(arrow_span_width, span_end)
				end
			end
			local pointer_width = 0
			if pointer_data then
				pointer_width = pointer_data.col + safe_utf8_len(pointer_data.arrow)
			end
			local effective_line_width = (pointer_data and rendered_line_width) or 0
			local line_arrow_width = math.max(arrow_span_width, pointer_width, effective_line_width) + arrow_end_space

			for arrow_index, line_label in ipairs(arrow_labels) do
				local span_len = span_length(line_label.label.char_span)
				local needs_pre_connectors = not config:get_option("compact") and (span_len == 0 or pointer_data ~= nil)
				if needs_pre_connectors then
					draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = false, is_ellipsis = false })
					local connectors = {}
					for col = 0, line_arrow_width - 1 do
						local draw_connector = false
						if pointer_data and col == pointer_data.col then
							draw_connector = true
						elseif span_len == 0 and col == line_label.col then
							draw_connector = true
						end
						if draw_connector then
							connectors[#connectors + 1] = draw.vbar
						else
							connectors[#connectors + 1] = " "
						end
					end
					buffer[#buffer + 1] = rtrim(table.concat(connectors))
					buffer[#buffer + 1] = "\n"
				end

				draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = false, is_ellipsis = false })

				local arrow_line = {}
				for col = 0, line_arrow_width - 1 do
					if col == line_label.col then
						local corner = draw.lbot
						if line_label.multi and not line_label.draw_message then
							corner = draw.rbot
						end
						arrow_line[#arrow_line + 1] = corner
					elseif col > line_label.col then
						arrow_line[#arrow_line + 1] = draw.hbar
					else
						arrow_line[#arrow_line + 1] = " "
					end
				end

				buffer[#buffer + 1] = rtrim(table.concat(arrow_line))
				if line_label.draw_message then
					buffer[#buffer + 1] = " " .. (line_label.label.display.message or "")
				else
					buffer[#buffer + 1] = ""
				end
				buffer[#buffer + 1] = "\n"

				if not config:get_option("compact") and arrow_index < #arrow_labels then
					draw_margin(buffer, draw, config, line_no_width, { line_index = line_index, is_line = false, is_ellipsis = false })
					local connectors = {}
					for col = 0, line_arrow_width - 1 do
						local draw_connector = false
						if pointer_data and col == pointer_data.col then
							draw_connector = true
						else
							for pending = arrow_index + 1, #arrow_labels do
								local pending_col = arrow_labels[pending].col
								if pending_col >= 0 and pending_col == col then
									draw_connector = true
									break
								end
							end
						end
						if draw_connector then
							connectors[#connectors + 1] = draw.vbar
						else
							connectors[#connectors + 1] = " "
						end
					end
					buffer[#buffer + 1] = rtrim(table.concat(connectors))
					buffer[#buffer + 1] = "\n"
				end

			end

			::continue_line::
		end

		if group_index == #groups then
			for help_index, help_text in ipairs(report.helps) do
				if not config:get_option("compact") then
					draw_margin(buffer, draw, config, line_no_width, { line_index = 0, is_line = false, is_ellipsis = false })
					buffer[#buffer + 1] = "\n"
				end
				local help_prefix = #report.helps > 1 and string.format("Help %d", help_index) or "Help"
				local help_prefix_len = (#report.helps > 1) and #help_prefix or 4
				local help_lines = split_lines(help_text)
				for line_idx, line_text in ipairs(help_lines) do
					draw_margin(buffer, draw, config, line_no_width, { line_index = 0, is_line = false, is_ellipsis = false })
					local content
					if line_idx == 1 then
						content = string.format("%s: %s", help_prefix, line_text)
					else
						content = repeat_char(" ", help_prefix_len + 2) .. line_text
					end
					if config:get_option("compact") then
						buffer[#buffer + 1] = " " .. content .. "\n"
					else
						buffer[#buffer + 1] = content .. "\n"
					end
				end
			end

			for note_index, note_text in ipairs(report.notes) do
				if not config:get_option("compact") then
					draw_margin(buffer, draw, config, line_no_width, { line_index = 0, is_line = false, is_ellipsis = false })
					buffer[#buffer + 1] = "\n"
				end
				local note_prefix = #report.notes > 1 and string.format("Note %d", note_index) or "Note"
				local note_prefix_len = (#report.notes > 1) and #note_prefix or 4
				local note_lines = split_lines(note_text)
				for line_idx, line_text in ipairs(note_lines) do
					draw_margin(buffer, draw, config, line_no_width, { line_index = 0, is_line = false, is_ellipsis = false })
					local content
					if line_idx == 1 then
						content = string.format("%s: %s", note_prefix, line_text)
					else
						content = repeat_char(" ", note_prefix_len + 2) .. line_text
					end
					if config:get_option("compact") then
						buffer[#buffer + 1] = " " .. content .. "\n"
					else
						buffer[#buffer + 1] = content .. "\n"
					end
				end
			end
		end

		if not config:get_option("compact") then
			local tail_prefix = repeat_char(draw.hbar, line_no_width + 2)
			buffer[#buffer + 1] = string.format("%s%s\n", tail_prefix, draw.rbot)
		end
	end

	return result()
end

--[[
Public API
]]

function ariadne.config()
	return make_config()
end

function ariadne.source(text)
	return new_source(text)
end

function ariadne.span(start_pos, finish_pos)
	return make_span(start_pos, finish_pos)
end

function ariadne.label(start_pos, finish_pos)
	return new_label(start_pos, finish_pos)
end

function ariadne.report(kind, span_obj)
	return new_report(kind, span_obj)
end

function ariadne.render(report, source)
	return render_report(report, source)
end

--[[
Color generator placeholder (exposed for tests)
]]

-- ColorGenerator mimics the deterministic color cycling used in the Rust implementation.
local ColorGenerator = {}
ColorGenerator.__index = ColorGenerator

function ColorGenerator:next()
	self.state = (self.state * 40503 + 1130) % 256
	return self.state
end

function ariadne.color_generator()
	return setmetatable({ state = 1 }, ColorGenerator)
end

return ariadne
