local ariadne = {}

--[[
Utility helpers
]]

local utf8 = utf8

-- repeat_char mirrors string.rep but guards against negative counts.
local function repeat_char(ch, count)
	return count >= 0 and string.rep(ch, count) or ""
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

-- trim_end removes trailing whitespace and returns a single string value.
local function trim_end(text)
	return text:gsub("%s+$", "")
end

local function split_lines(text)
	local lines = {}
	for line in (text .. "\n" or "\n"):gmatch "(.-)\n" do
		lines[#lines + 1] = line
	end
	return lines
end

--[[
Characters (draw set)
]]

ariadne.unicode = {
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
}

ariadne.ascii = {
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
}

--[[
Config implementation
]]

local DEFAULT_CONFIG = {
	cross_gap = true,
	label_attach = "middle",
	compact = false,
	underlines = true,
	multiline_arrows = true,
	color = true,
	tab_width = 4,
	char_set = ariadne.unicode,
	index_type = "char",
}

local function get_attach(config)
	local value = config.label_attach
	assert(value == "start" or value == "middle" or value == "end", "label_attach must be start, middle, or end")
	return value
end

local function get_index_type(config)
	local value = config.index_type
	assert(value == "byte" or value == "char", "index_type must be byte or char")
	return value
end

-- make_config builds a config instance seeded from defaults or an existing snapshot.
local function make_config(base)
	local t = base or {}
	for k, v in pairs(DEFAULT_CONFIG) do
		if t[k] == nil then
			t[k] = v
		end
	end
	return t
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
				offset = 1,
				char_len = 0,
				byte_offset = 0,
				byte_len = 0,
				text = "",
				has_utf8 = false,
			},
		}
	end

	local lines = {}
	local total_chars = 0
	local total_bytes = 1
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
		local char_len = utf8.len(line_text)
		local byte_len = #line_text

		lines[#lines + 1] = {
			offset = total_chars + 1,
			char_len = char_len,
			byte_offset = total_bytes,
			byte_len = byte_len,
			text = line_text,
			has_utf8 = not line_text:find("^[\0-\x7f]*$"),
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

	-- line retrieves the raw line record at a 1-based index.
function Source:line(index)
	return self.lines[index]
end

	-- get_line_text unwraps the line struct to expose the stored text.
function Source:get_line_text(line)
	local _ = self
	return line.text
end

-- binary_search locates the greatest line index whose key is <= target.
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

-- line_index_for_offset finds the line containing the char offset (1-based).
function Source:line_index_for_offset(offset)
	if offset <= 0 then return 0 end
	return binary_search(self.lines, offset, "offset")
end

-- line_index_for_byte finds the line containing the byte offset (1-based).
function Source:line_index_for_byte(byte_offset)
	if byte_offset <= 0 then return 0 end
	return binary_search(self.lines, byte_offset, "byte_offset")
end

-- get_offset_line returns the line record, index, and relative char column.
function Source:get_offset_line(offset)
	if offset > self.char_len + 1 then return nil end
	local idx = self:line_index_for_offset(offset)
	local line = self.lines[idx]
	if not line then return nil end
	return line, idx, offset - line.offset + 1
end

-- char_count_for_prefix converts a byte prefix into a character length.
local function char_count_for_prefix(line, byte_count)
	if byte_count <= 0 then
		return 0
	end
	if line.has_utf8 then
		return utf8.len(line.text, 1, byte_count)
	end
	return byte_count
end

-- split_at_column divides text into the prefix and suffix around the given char column.
local function split_at_column(text, column)
	if column <= 1 then
		return "", text
	end
	local byte_index = utf8.offset(text, column)
	if not byte_index then
		return text, ""
	end
	return text:sub(1, byte_index - 1), text:sub(byte_index)
end

-- get_byte_line returns the line record, index, and relative byte column for a byte offset.
function Source:get_byte_line(byte_offset)
	if byte_offset > self.byte_len then return nil end
	local idx = self:line_index_for_byte(byte_offset)
	local line = self.lines[idx]
	if not line then return nil end
	return line, idx, byte_offset - line.byte_offset + 1
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
	local end_line = self:line_index_for_offset(end_lookup)

	return { start = start_line, finish = end_line }
end

--[[
Span helpers
]]

-- make_span normalises the provided start/finish positions into a table.
local function make_span(start_pos, finish_pos)
	assert(finish_pos >= start_pos-1, "span finish must be >= start-1")
	return { start = start_pos, finish = finish_pos }
end

-- span_length returns the non-negative length of the span.
local function span_length(span)
	return math.max(span.finish - span.start + 1, 0)
end

-- span_last_offset gives the greatest in-range offset for inclusive comparisons.
local function span_last_offset(span)
	return span.start <= span.finish and span.finish or span.start
end

--[[
Label implementation
]]

local Label = {}
Label.__index = Label

local function new_label(start_pos, finish_pos)
	return setmetatable({
		span = make_span(start_pos, finish_pos),
        display = {
			message = nil,
			color = nil,
			order = 0,
			priority = 0,
		}
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
			config = DEFAULT_CONFIG,
		},
	}, ReportBuilder)
end

function ReportBuilder:config(cfg)
	self._state.config = cfg
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
Label grouping helpers
]]

-- index_to_char_offset converts an incoming offset into a character offset for rendering.
local function index_to_char_offset(source, config, offset)
	if get_index_type(config) == "char" then
		return offset
	end
	local line, _, byte_column = source:get_byte_line(offset)
	if not line then
		return offset
	end
	local chars_before = char_count_for_prefix(line, byte_column - 1)
	return line.offset + chars_before
end

-- index_range_to_char_span maps the incoming span into character offsets for rendering.
local function index_range_to_char_span(source, config, span)
	if get_index_type(config) == "char" then
		local start_line, start_idx = source:get_offset_line(span.start)
		if not start_line then return nil end
		local char_start = span.start
		local end_line, char_end
		if span.start > span.finish then
			end_line, char_end = start_idx, char_start-1
		else
			local _, end_idx = source:get_offset_line(span.finish)
			if not end_idx then return nil end
			end_line, char_end = end_idx, span.finish
		end
		return {
			start = char_start,
			finish = char_end,
			start_line = start_idx,
			end_line = end_line,
		}
	end

	local start_line, start_idx, start_byte_col = source:get_byte_line(span.start)
	if not start_line then return nil end
	local start_chars = char_count_for_prefix(start_line, start_byte_col - 1)
	local char_start = start_line.offset + start_chars

	local char_end, end_line_idx
	if span.start > span.finish then
        end_line_idx, char_end = start_idx, char_start-1
	else
		local end_pos = span.finish
		local end_line, end_idx, end_byte_col = source:get_byte_line(end_pos)
		if not end_line then return nil end
		local chars_until_end = char_count_for_prefix(end_line, end_byte_col)
		char_end, end_line_idx = end_line.offset + chars_until_end - 1, end_idx
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
	local kind = "multiline"
	if char_span.start_line == char_span.end_line then
		kind = "inline"
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
			local group_span = group.char_span
			local start = group_span.start
			if not start or start > char_span.start then
				group_span.start = char_span.start
			end
			local finish = group_span.finish
			if not finish or finish < char_span.finish then
				group_span.finish = char_span.finish
			end
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
		line = tostring((idx or 1) + source.display_line_offset),
		column = tostring(column or 1),
	}
end

-- draw_margin emits the gutter prefix for a given line or spacer.
local function draw_margin(b, config, line_no_width, line_index, bar)
	b[#b+1] = " "
	if line_index then
		local line_no = tostring(line_index)
		b[#b+1] = repeat_char(" ", line_no_width - #line_no)
		b[#b+1] = line_no
		b[#b+1] = " "
	else
		b[#b+1] = repeat_char(" ", line_no_width + 1)
	end
	b[#b+1] =  bar

	if not config.compact then
		b[#b+1] = " "
	end
end

-- render_report assembles the formatted diagnostic into a single string buffer by walking
-- each source group, drawing the margin, inline highlights, arrow lines, and trailing
-- help/note sections. It mirrors the Rust formatter closely so we can diff behaviour.
-- render_report mirrors ariadne's Rust formatter so snapshot comparisons line up.
local function render_report(report, source)
	local config = report.config
	local draw = config.char_set

	-- Stage labels by source file; Rust keeps identical structure for deterministic output.
	local groups = compute_source_groups(report, source)

	local buffer = {}
	buffer[#buffer + 1] = format_code(report.code)
	buffer[#buffer + 1] = report.kind
	buffer[#buffer + 1] = ": "
	buffer[#buffer + 1] = report.message or ""
	buffer[#buffer + 1] = "\n"

	if #groups == 0 then
		return table.concat(buffer)
	end

	local line_no_width = 0
	for _, group in ipairs(groups) do
		local range = source:get_line_range(group.char_span)
		group.line_range = range
		group.source_name = "<unknown>"
		group.primary_location = make_location(source, config, report.span)
		line_no_width = math.max(line_no_width, digits(range.finish + source.display_line_offset))
	end

	for group_index, group in ipairs(groups) do
		local range = group.line_range
		local prefix = repeat_char(" ", line_no_width + 2)
		buffer[#buffer + 1] = prefix
		buffer[#buffer + 1] = group_index == 1 and draw.ltop or draw.lcross
		buffer[#buffer + 1] = draw.hbar
		buffer[#buffer + 1] = draw.lbox
		buffer[#buffer + 1] = string.format(" %s:%s:%s ", group.source_name, group.primary_location.line, group.primary_location.column)
		buffer[#buffer + 1] = draw.rbox
		buffer[#buffer + 1] = "\n"

		if not config.compact then
			buffer[#buffer + 1] = prefix
			buffer[#buffer + 1] = draw.vbar
			buffer[#buffer + 1] = "\n"
		end

		-- multi_labels hold every span that stretches over multiple lines so we can render gutter guides.
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

		for line_index = range.start, range.finish do
			local line = source:line(line_index)
			if not line then
				goto continue_line
			end

			local line_text = trim_end(source:get_line_text(line))

			-- Collect inline spans and multi-span endpoints that touch this line.
			local line_labels = {}

			for _, label in ipairs(group.labels) do
				if label.kind == "inline" and line_index == label.start_line then
					local attach
					local config_attach = get_attach(config)
					if config_attach == "start" then
						attach = label.char_span.start
					elseif config_attach == "end" then
						attach = label_last_offset(label)
					else
						attach = (label.char_span.start + label.char_span.finish + 1) // 2
					end
					line_labels[#line_labels + 1] = {
						col = attach - line.offset + 1,
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
						col = label.char_span.start - line.offset + 1
					else
						col = math.max(label.char_span.start - line.offset + 1, 1)
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
					-- Rust prints ':' rows between multi-line label edges when interior lines are omitted.
					draw_margin(buffer, config, line_no_width, nil, draw.vbar_gap)
					buffer[#buffer + 1] = ":\n"
					is_ellipsis = true
					goto continue_line
				end
				if not config.compact and not is_ellipsis then
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
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

			-- pointer_data mirrors Rust's "LineLabel" margin pointer that precedes multi-line arrows.
			local pointer_data
			for _, ll in ipairs(line_labels) do
				if ll.multi then
					local col = math.max(ll.col, 1)
					pointer_data = {
						col = col,
						-- Matches Rust's glyph selection: use vertical pipe for end rows, elbow for starts.
						arrow = (ll.draw_message and draw.vbar or draw.ltop) .. draw.hbar .. draw.rarrow .. " ",
					}
					break
				end
			end

			local display_line_no = line_index + source.display_line_offset
			draw_margin(buffer, config, line_no_width, display_line_no, draw.vbar)

			local text_row = line_text
			if pointer_data then
				-- Insert the multi-line pointer arrow into the rendered text, padding to the insertion column.
				local col = pointer_data.col
				local text_prefix, suffix = split_at_column(line_text, col)
				local prefix_len = utf8.len(text_prefix)
				if prefix_len < col-1 then
					text_prefix = text_prefix .. repeat_char(" ", col - prefix_len)
				end
				text_row = text_prefix .. pointer_data.arrow .. suffix
			end

			buffer[#buffer + 1] = text_row
			buffer[#buffer + 1] = "\n"
			local rendered_line_width = utf8.len(text_row)
			-- arrow_labels filters to spans that actually emit arrow messages on this line.
			local arrow_labels = {}
			for _, line_label in ipairs(line_labels) do
				if line_label.label.display.message and (not line_label.multi or line_label.draw_message) then
					arrow_labels[#arrow_labels + 1] = line_label
				end
			end

			-- Track the highest-priority highlight per column so multiple inline labels can overlap.
			if not config.compact then
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
					local start_col = math.max(span_start - line.offset + 1, 1)
					local end_col = math.max(span_finish - line.offset + 1, start_col-1)
					local candidate = {
						priority = display.priority or 0,
						span_len = span_length(line_label.label.char_span),
					}
					for col = start_col, end_col do
						if col >= 1 then
							if better_highlight(highlight_meta[col], candidate) then
								candidate.cell = draw.underline
								highlight_meta[col] = candidate
							end
						end
					end
					local attach_col = line_label.col
					if attach_col >= 1 and attach_col <= line.char_len then
						local attach_candidate = {
							priority = candidate.priority,
							span_len = 0,
							cell = draw.underbar,
						}
						if better_highlight(highlight_meta[attach_col], attach_candidate) then
							highlight_meta[attach_col] = attach_candidate
						end
					end
					::continue_label_highlight::
				end

				local has_highlight = false
				local highlight_chars = {}
				for col = 1, line.char_len + 1 do
					local ch = highlight_meta[col] and highlight_meta[col].cell or " "
					highlight_chars[#highlight_chars + 1] = ch
					if ch ~= " " then
						has_highlight = true
					end
				end
				if has_highlight then
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					for _, c in ipairs(highlight_chars) do
						buffer[#buffer+1] = c
					end
					buffer[#buffer + 1] = "\n"
				end
			end

			-- Rust reserves a trailing gap so text after the arrow stays readable.
			local arrow_end_space = config.compact and 1 or 2
			local arrow_span_width = 0
			for _, ll in ipairs(line_labels) do
				if ll.multi then
					arrow_span_width = math.max(arrow_span_width, line.char_len)
				else
					local span_end = math.max(ll.label.char_span.finish - line.offset + 1, 0)
					arrow_span_width = math.max(arrow_span_width, span_end)
				end
			end
			local pointer_width = 0
			if pointer_data then
				-- Include the pointer glyph width
				pointer_width = pointer_data.col + utf8.len(pointer_data.arrow) - 1
			end
			local effective_line_width = (pointer_data and rendered_line_width) or 0
			local line_arrow_width = math.max(arrow_span_width, pointer_width, effective_line_width) + arrow_end_space

			for arrow_index, line_label in ipairs(arrow_labels) do
				-- Pre-arrow connector rows keep vertical guides alive above zero-length spans or pointer joins.
				local span_len = span_length(line_label.label.char_span)
				local needs_pre_connectors = not config.compact and (span_len == 0 or pointer_data ~= nil)
				if needs_pre_connectors then
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					for col = 1, line_arrow_width do
						local draw_connector = false
						if pointer_data and col == pointer_data.col then
							draw_connector = true
						elseif span_len == 0 and col == line_label.col then
							draw_connector = true
						end
						if draw_connector then
							buffer[#buffer + 1] = draw.vbar
							break
						else
							buffer[#buffer + 1] = " "
						end
					end
					buffer[#buffer + 1] = "\n"
				end

				draw_margin(buffer, config, line_no_width, nil, draw.vbar)

				for col = 1, line_arrow_width do
					if col == line_label.col then
						local corner = draw.lbot
						if line_label.multi and not line_label.draw_message then
							corner = draw.rbot
						end
						buffer[#buffer + 1] = corner
					elseif col > line_label.col then
						buffer[#buffer + 1] = draw.hbar
					else
						local cell = " "
						if pointer_data and col == pointer_data.col then
							cell = draw.vbar
						else
							for pending = arrow_index + 1, #arrow_labels do
								local pending_col = arrow_labels[pending].col
								if pending_col >= 1 and pending_col == col then
									cell = draw.vbar
									break
								end
							end
						end
						buffer[#buffer + 1] = cell
					end
				end

				if line_label.draw_message then
					buffer[#buffer + 1] = " "
					buffer[#buffer + 1] = line_label.label.display.message or nil
				end
				buffer[#buffer + 1] = "\n"

				-- Post-arrow connectors ensure pending arrows line up in subsequent rows.
				if not config.compact and arrow_index < #arrow_labels then
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					local connectors = {}
					for col = 1, line_arrow_width do
						local draw_connector = false
						if pointer_data and col == pointer_data.col then
							draw_connector = true
						else
							for pending = arrow_index + 1, #arrow_labels do
								local pending_col = arrow_labels[pending].col
								if pending_col >= 1 and pending_col == col then
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
					buffer[#buffer + 1] = trim_end(table.concat(connectors))
					buffer[#buffer + 1] = "\n"
				end

			end

			::continue_line::
		end

		if group_index == #groups then
			for help_index, help_text in ipairs(report.helps) do
				-- Match Rust by inserting blank spacer rows when not compact.
				if not config.compact then
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					buffer[#buffer + 1] = "\n"
				end
				local help_prefix = #report.helps > 1 and string.format("Help %d", help_index) or "Help"
				local help_prefix_len = (#report.helps > 1) and #help_prefix or 4
				local help_lines = split_lines(help_text)
				for line_idx, line_text in ipairs(help_lines) do
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					local content
					if line_idx == 1 then
						content = string.format("%s: %s", help_prefix, line_text)
					else
						content = repeat_char(" ", help_prefix_len + 2) .. line_text
					end
					buffer[#buffer + 1] = content
					buffer[#buffer + 1] = "\n"
				end
			end

			for note_index, note_text in ipairs(report.notes) do
				if not config.compact then
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					buffer[#buffer + 1] = "\n"
				end
				local note_prefix = #report.notes > 1 and string.format("Note %d", note_index) or "Note"
				local note_prefix_len = (#report.notes > 1) and #note_prefix or 4
				local note_lines = split_lines(note_text)
				for line_idx, line_text in ipairs(note_lines) do
					draw_margin(buffer, config, line_no_width, nil, draw.vbar)
					local content
					if line_idx == 1 then
						content = string.format("%s: %s", note_prefix, line_text)
					else
						content = repeat_char(" ", note_prefix_len + 2) .. line_text
					end
					buffer[#buffer + 1] = content
					buffer[#buffer + 1] = "\n"
				end
			end
		end

		if not config.compact then
			buffer[#buffer + 1] = repeat_char(draw.hbar, line_no_width + 2)
			buffer[#buffer + 1] = draw.rbot
			buffer[#buffer + 1] = "\n"
		end
	end

	return table.concat(buffer)
end

--[[
Public API
]]

function ariadne.config(base)
	return make_config(base)
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

function ariadne.error(span_obj)
    return new_report("Error", span_obj)
end

function ariadne.warning(span_obj)
    return new_report("Warning", span_obj)
end

function ariadne.advice(span_obj)
    return new_report("Advice", span_obj)
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
