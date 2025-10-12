local luaunit = require("luaunit")

local ariadne = require("ariadne")

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

local function no_color_ascii()
	return ariadne.config()
		:color(false)
		:char_set("ascii")
end

local function source(text)
	return ariadne.source(text)
end

local TestWrite = {}

function TestWrite.test_one_message()
	local msg = remove_trailing(
		ariadne.report("error", ariadne.span(0, 0))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 5))
			:label(ariadne.label(9, 15))
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

function TestWrite.test_two_labels_with_messages()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 5):message("This is an apple"))
			:label(ariadne.label(9, 15):message("This is an orange"))
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
---'
]=]))
end

function TestWrite.test_multi_byte_chars()
	local text = "äpplë == örängë;"
	local msg = remove_trailing(
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii():index_type("char"))
			:message("can't compare äpplës with örängës")
			:label(ariadne.label(0, 5):message("This is an äpplë"))
			:label(ariadne.label(9, 15):message("This is an örängë"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii():index_type("byte"))
			:message("can't compare äpplës with örängës")
			:label(ariadne.label(0, 7):message("This is an äpplë"))
			:label(ariadne.label(11, 20):message("This is an örängë"))
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
		ariadne.report("error", ariadne.span(11, 11))
			:config(no_color_ascii():index_type("byte"))
			:message("can't compare äpplës with örängës")
			:label(ariadne.label(0, 7):message("This is an äpplë"))
			:label(ariadne.label(11, 20):message("This is an örängë"))
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
		ariadne.report("error", ariadne.span(0, 0))
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
   |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                      ^^|^^
   |                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                                        `---- This is an orange
---'
]=]))
end

function TestWrite.test_label_of_width_zero_at_end_of_line()
	local text = "apple ==\n"
	local msg = remove_trailing(
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii():index_type("byte"))
			:message("unexpected end of file")
			:label(ariadne.label(9, 9):message("Unexpected end of file"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(0, 0):message("No more fruit!"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(0, 0):message("No more fruit!"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(0, 0):message("No more fruit!"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("unexpected end of file")
			:label(ariadne.label(0, 0):message("No more fruit!"))
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

	for i = 0, #text do
		for j = i, #text do
			local ok, result = pcall(function()
				return ariadne.report("error", ariadne.span(0, 0))
					:config(no_color_ascii():index_type("byte"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:label(ariadne.label(0, #text):message("illegal comparison"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:label(ariadne.label(0, #text):message("URL"))
			:label(ariadne.label(0, colon_start):message("scheme"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 5):message("This is an apple"))
			:label(ariadne.label(0, 5):message("Have I mentioned that this is an apple?"))
			:label(ariadne.label(0, 5):message("No really, have I mentioned that?"))
			:label(ariadne.label(9, 15):message("This is an orange"))
			:label(ariadne.label(9, 15):message("Have I mentioned that this is an orange?"))
			:label(ariadne.label(9, 15):message("No really, have I mentioned that?"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 5):message("This is an apple"))
			:label(ariadne.label(9, 15):message("This is an orange"))
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

function TestWrite.test_help()
	local text = "apple == orange;"
	local msg = remove_trailing(
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 5):message("This is an apple"))
			:label(ariadne.label(9, 15):message("This is an orange"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 5):message("This is an apple"))
			:label(ariadne.label(9, 15):message("This is an orange"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 15):message("This is a strange comparison"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 15):message("This is a strange comparison"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 15):message("This is a strange comparison"))
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
		ariadne.report("error", ariadne.span(0, 0))
			:config(no_color_ascii())
			:message("can't compare apples with oranges")
			:label(ariadne.label(0, 15):message("This is a strange comparison"))
			:help("No need to try, they can't be compared.")
			:help("Yeah, really, please stop.\nIt has no resemblance.")
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
   | Help 1: No need to try, they can't be compared.
   |
   | Help 2: Yeah, really, please stop.
   |         It has no resemblance.
---'
]=]))
end

local TestDraw = {}

function TestDraw.test_const_colors()
	local gen = ariadne.color_generator()
	local first = gen:next()
	local second = gen:next()
	local third = gen:next()

	luaunit.assertNotEquals(first, second)
	luaunit.assertNotEquals(second, third)
	luaunit.assertNotEquals(third, first)
end

_G.TestWrite = TestWrite
-- _G.TestDraw = TestDraw

os.exit(luaunit.LuaUnit.run())
