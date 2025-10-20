local luaunit = require "luaunit"
local _ = require "luacov"

local ariadne = require "ariadne"

local function remove_trailing(text)
	local out = {}
	local start = 1

	while true do
		local stop = text:find("\n", start, true)
		if not stop then
			if start <= #text then
				local line = text:sub(start)
				local trimmed = line:gsub("%s+$", "")
				table.insert(out, trimmed)
				table.insert(out, "\n")
			end
			break
		end

		local line = text:sub(start, stop - 1)
		local trimmed = line:gsub("%s+$", "")
		table.insert(out, trimmed)
		table.insert(out, "\n")
		start = stop + 1
	end

	return table.concat(out)
end

local function no_color_ascii(index_type, compact)
    return ariadne.config {
		color = false,
		char_set = ariadne.ascii,
		index_type = index_type,
		compact = compact,
	}
end

local function source(text)
	return ariadne.source(text)
end

local TestWrite = {}

function TestWrite.test_one_message()
	local msg = remove_trailing(
		ariadne.error(ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:finish()
			:write_to_string(source(""))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
]=]))
end

function TestWrite.test_two_labels_without_messages()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5))
			:label(ariadne.label(10, 15))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
---'
]=]))
end

function TestWrite.test_label_attach_start_with_blank_line()
	local text = "alpha\nbravo\ncharlie\n"
	local cfg = no_color_ascii()
	cfg.label_attach = "start"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | alpha
   | ^^|^^
   |   `---- This is an apple
 2 | bra,-> vo
 3 | |-> charlie
   | |
   | `------------ This is an orange
---'
]=]))
end

function TestWrite.test_two_labels_with_messages_compact()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii(nil, true))
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
 1 |apple == orange;
   |  `------------- This is an apple
   |            `--- This is an orange
]=]))
end

function TestWrite.test_multi_byte_chars()
	local text = "äpplë == örängë;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii "char")
			:message("can't compare äpplës with örängës")
			:label(ariadne.label(1, 5):message("This is an äpplë"))
			:label(ariadne.label(10, 15):message("This is an örängë"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare äpplës with örängës
   ,-[ <unknown>:1:1 ]
   |
 1 | äpplë == örängë;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an äpplë
   |             |
   |             `---- This is an örängë
---'
]=]))
end

function TestWrite.test_byte_label()
	local text = "äpplë == örängë;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii "byte")
			:message("can't compare äpplës with örängës")
			:label(ariadne.label(1, 7):message("This is an äpplë"))
			:label(ariadne.label(12, 20):message("This is an örängë"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare äpplës with örängës
   ,-[ <unknown>:1:1 ]
   |
 1 | äpplë == örängë;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an äpplë
   |             |
   |             `---- This is an örängë
---'
]=]))
end

function TestWrite.test_byte_column()
	local text = "äpplë == örängë;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(12, 12))
			:config(no_color_ascii "byte")
			:message("can't compare äpplës with örängës")
			:label(ariadne.label(1, 7):message("This is an äpplë"))
			:label(ariadne.label(12, 20):message("This is an örängë"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare äpplës with örängës
   ,-[ <unknown>:1:10 ]
   |
 1 | äpplë == örängë;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an äpplë
   |             |
   |             `---- This is an örängë
---'
]=]))
end

function TestWrite.test_label_at_end_of_long_line()
	local text = string.rep("apple == ", 100) .. "orange"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(#text - 5, #text):message("This is an orange"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == apple == orange
   |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                     ^^^|^^
   |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        `---- This is an orange
---'
]=]))
end

function TestWrite.test_label_of_width_zero_at_end_of_line()
	local text = "apple ==\n"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii "byte")
			:message("unexpected end of file")
			:label(ariadne.label(10, 9):message("Unexpected end of file"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: unexpected end of file
   ,-[ <unknown>:1:1 ]
   |
 1 | apple ==
   |          |
   |          `- Unexpected end of file
---'
]=]))
end

function TestWrite.test_empty_input()
	local text = ""
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(1, 0):message("No more fruit!"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: unexpected end of file
   ,-[ <unknown>:1:1 ]
   |
 1 |
   | |
   | `- No more fruit!
---'
]=]))
end

function TestWrite.test_empty_input_help()
	local text = ""
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(1, 0):message("No more fruit!"))
			:help("have you tried going to the farmer's market?")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: unexpected end of file
   ,-[ <unknown>:1:1 ]
   |
 1 |
   | |
   | `- No more fruit!
   |
   | Help: have you tried going to the farmer's market?
---'
]=]))
end

function TestWrite.test_empty_input_note()
	local text = ""
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(1, 0):message("No more fruit!"))
			:note("eat your greens!")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: unexpected end of file
   ,-[ <unknown>:1:1 ]
   |
 1 |
   | |
   | `- No more fruit!
   |
   | Note: eat your greens!
---'
]=]))
end

function TestWrite.test_empty_input_help_note()
	local text = ""
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(1, 0):message("No more fruit!"))
			:note("eat your greens!")
			:help("have you tried going to the farmer's market?")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: unexpected end of file
   ,-[ <unknown>:1:1 ]
   |
 1 |
   | |
   | `- No more fruit!
   |
   | Help: have you tried going to the farmer's market?
   |
   | Note: eat your greens!
---'
]=]))
end

function TestWrite.test_byte_spans_never_crash()
	local text = "apple\np\n\nempty\n"

	for i = 1, #text do
		for j = i, #text do
			local ok, result = pcall(function()
				return ariadne.error(ariadne.span(1, 1))
					:config(no_color_ascii "byte")
					:message("Label")
					:label(ariadne.label(i, j):message("Label"))
					:finish()
					:write_to_string(source(text))
			end)
			luaunit.assertTrue(ok)
			luaunit.assertEquals(type(result), "string")
		end
	end
end

function TestWrite.test_multiline_label()
	local text = "apple\n==\norange"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:label(ariadne.label(1, #text):message("illegal comparison"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error:
   ,-[ <unknown>:1:1 ]
   |
 1 | ,-> apple
   : :
 3 | |-> orange
   | |
   | `----------- illegal comparison
---'
]=]))
end

function TestWrite.test_partially_overlapping_labels()
	local text = "https://example.com/"
	local colon_start = assert(text:find(":", 1, true)) - 1
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:label(ariadne.label(1, #text):message("URL"))
			:label(ariadne.label(1, colon_start):message("scheme"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error:
   ,-[ <unknown>:1:1 ]
   |
 1 | https://example.com/
   | ^^|^^^^^^^|^^^^^^^^^
   |   `------------------- scheme
   |           |
   |           `----------- URL
---'
]=]))
end

function TestWrite.test_multiple_labels_same_span()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(1, 5):message("Have I mentioned that this is an apple?"))
			:label(ariadne.label(1, 5):message("No really, have I mentioned that?"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:label(ariadne.label(10, 15):message("Have I mentioned that this is an orange?"))
			:label(ariadne.label(10, 15):message("No really, have I mentioned that?"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an apple
   |   |         |
   |   `-------------- Have I mentioned that this is an apple?
   |   |         |
   |   `-------------- No really, have I mentioned that?
   |             |
   |             `---- This is an orange
   |             |
   |             `---- Have I mentioned that this is an orange?
   |             |
   |             `---- No really, have I mentioned that?
---'
]=]))
end

function TestWrite.test_note()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:note("stop trying ... this is a fruitless endeavor")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an apple
   |             |
   |             `---- This is an orange
   |
   | Note: stop trying ... this is a fruitless endeavor
---'
]=]))
end

function TestWrite.test_note_compact()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii(nil, true))
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:note("stop trying ... this is a fruitless endeavor")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
 1 |apple == orange;
   |  `------------- This is an apple
   |            `--- This is an orange
   |Note: stop trying ... this is a fruitless endeavor
]=]))
end

function TestWrite.test_help()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:help("have you tried peeling the orange?")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an apple
   |             |
   |             `---- This is an orange
   |
   | Help: have you tried peeling the orange?
---'
]=]))
end

function TestWrite.test_help_and_note()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 5):message("This is an apple"))
			:label(ariadne.label(10, 15):message("This is an orange"))
			:help("have you tried peeling the orange?")
			:note("stop trying ... this is a fruitless endeavor")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^|^^    ^^^|^^
   |   `-------------- This is an apple
   |             |
   |             `---- This is an orange
   |
   | Help: have you tried peeling the orange?
   |
   | Note: stop trying ... this is a fruitless endeavor
---'
]=]))
end

function TestWrite.test_single_note_single_line()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 15):message("This is a strange comparison"))
			:note("No need to try, they can't be compared.")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^^^^^^|^^^^^^^
   |        `--------- This is a strange comparison
   |
   | Note: No need to try, they can't be compared.
---'
]=]))
end

function TestWrite.test_multi_notes_single_lines()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 15):message("This is a strange comparison"))
			:note("No need to try, they can't be compared.")
			:note("Yeah, really, please stop.")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^^^^^^|^^^^^^^
   |        `--------- This is a strange comparison
   |
   | Note 1: No need to try, they can't be compared.
   |
   | Note 2: Yeah, really, please stop.
---'
]=]))
end

function TestWrite.test_multi_notes_multi_lines()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 15):message("This is a strange comparison"))
			:note("No need to try, they can't be compared.")
			:note("Yeah, really, please stop.\nIt has no resemblance.")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^^^^^^|^^^^^^^
   |        `--------- This is a strange comparison
   |
   | Note 1: No need to try, they can't be compared.
   |
   | Note 2: Yeah, really, please stop.
   |         It has no resemblance.
---'
]=]))
end

function TestWrite.test_multi_helps_multi_lines()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.advice(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(1, 15):message("This is a strange comparison"))
			:help("No need to try, they can't be compared.")
			:help("Yeah, really, please stop.\nIt has no resemblance.")
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Advice: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^^^^^^|^^^^^^^
   |        `--------- This is a strange comparison
   |
   | Help 1: No need to try, they can't be compared.
   |
   | Help 2: Yeah, really, please stop.
   |         It has no resemblance.
---'
]=]))
end

function TestWrite.test_display_line_offset()
	local text = "first line\nsecond line\n"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("line offset demo")
			:label(ariadne.label(12, 22):message("Second line"))
			:finish()
			:write_to_string(source(text):with_display_line_offset(9))
	)

	luaunit.assertEquals(msg, ([=[
Error: line offset demo
    ,-[ <unknown>:10:1 ]
    |
 11 | second line
    | ^^^^^|^^^^^
    |      `------- Second line
----'
]=]))
end

function TestWrite.test_label_ordering()
	local text = "abcdef"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("ordered labels")
			:label(ariadne.label(1, 3):message("Left"))
			:label(ariadne.label(4, 6):order(-10):message("Right"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: ordered labels
   ,-[ <unknown>:1:1 ]
   |
 1 | abcdef
   | ^|^^|^
   |  |  `--- Right
   |  |
   |  `------ Left
---'
]=]))
end

function TestWrite.test_split_labels()
	local text = "alpha\nbravo\ncharlie\n"
	local cfg = no_color_ascii()
	cfg.label_attach = "start"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 15))
			:config(cfg)
			:message("gaps between labels")
			:label(ariadne.label(1, 5):message("first"))
			:label(ariadne.label(13, 19):message("third"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: gaps between labels
   ,-[ <unknown>:1:1 ]
   |
 1 | alpha
   | |^^^^
   | `------ first
   |
 3 | charlie
   | |^^^^^^
   | `-------- third
---'
]=]))
end

function TestWrite.test_zero_length_span()
	local text = "delta"
	local cfg = no_color_ascii()
	cfg.label_attach = "end"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(3, 2))
			:config(cfg)
			:message("zero length span")
			:label(ariadne.label(3, 2):message("point"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: zero length span
   ,-[ <unknown>:1:3 ]
   |
 1 | delta
   |   |
   |   |
   |   `- point
---'
]=]))
end

function TestWrite.test_priority_highlight_and_color()
	local text = "klmnop"
	local strong = ariadne.label(2, 5):message("strong"):priority(10):color("cyan")
	local weak = ariadne.label(1, 4):message("weak")
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("overlap priorities")
			:label(weak)
			:label(strong)
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: overlap priorities
   ,-[ <unknown>:1:1 ]
   |
 1 | klmnop
   | ^^^|^
   |   `---- weak
   |    |
   |    `--- strong
---'
]=]))
end

function TestWrite.test_multiple_arrow_connectors()
	local text = "qrstuvwx"
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("stacked arrows")
			:label(ariadne.label(1, 3):message("left"))
			:label(ariadne.label(5, 8):message("right"))
			:finish()
			:write_to_string(source(text))
	)

	luaunit.assertEquals(msg, ([=[
Error: stacked arrows
   ,-[ <unknown>:1:1 ]
   |
 1 | qrstuvwx
   | ^|^ ^^|^
   |  `-------- left
   |       |
   |       `--- right
---'
]=]))
end

function TestWrite.test_custom_report_with_code()
	local msg = remove_trailing(
		ariadne.report("Notice", ariadne.span(1, 1))
			:config(no_color_ascii())
			:code("E100")
			:message("custom kind")
			:finish()
			:write_to_string(source("x"))
	)

	luaunit.assertEquals(msg, ([=[
[E100] Notice: custom kind
]=]))
end

function TestWrite.test_warning_and_advice()
	local warning = remove_trailing(
		ariadne.warning(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("careful")
			:finish()
			:write_to_string(source("w"))
	)
	local advice = remove_trailing(
		ariadne.advice(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("consider")
			:finish()
			:write_to_string(source("a"))
	)

	luaunit.assertEquals(warning, ([=[
Warning: careful
]=]))
	luaunit.assertEquals(advice, ([=[
Advice: consider
]=]))
end

function TestWrite.test_byte_index_out_of_bounds()
	local cfg = no_color_ascii("byte")
	local msg = remove_trailing(
		ariadne.error(ariadne.span(100, 100))
			:config(cfg)
			:message("unknown position")
			:finish()
			:write_to_string(source("hi"))
	)

	luaunit.assertEquals(msg, ([=[
Error: unknown position
]=]))
end

function TestWrite.test_invalid_label_skipped()
	local msg = remove_trailing(
		ariadne.error(ariadne.span(1, 1))
			:config(no_color_ascii())
			:message("invalid label")
			:label(ariadne.label(999, 1000):message("ignored"))
			:finish()
			:write_to_string(source("short"))
	)

	luaunit.assertEquals(msg, ([=[
Error: invalid label
]=]))
end


local TestDraw = {}

function TestDraw.test_color_generator()
	local gen = ariadne.color_generator()
	local a, b, c = gen:next(), gen:next(), gen:next()
	luaunit.assertEquals(a, 161)
	luaunit.assertEquals(b, 1)
	luaunit.assertEquals(c, 161)
end

local TestSource = {}

function TestSource.test_line_range_clamps_finish()
	local src = ariadne.source("hello world")
	local range = src:get_line_range({ start = 2, finish = 1 })
	luaunit.assertEquals(range, { start = 1, finish = 1 })
end

_G.TestWrite = TestWrite
_G.TestDraw = TestDraw
_G.TestSource = TestSource

os.exit(luaunit.LuaUnit.run())
