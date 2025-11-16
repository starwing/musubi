local lu = require "luaunit"
local ariadne = require "ariadne"

---@param text string
---@return string
local function remove_trailing(text)
    return (text:gsub("%s+\n", "\n"):gsub("%s+\n$", "\n"))
end

local TestSource = {}
do
    local function get_line_text(src, line)
        return src.text:sub(line:byte_span())
    end

    local function test_with_lines(lines)
        local code = table.concat(lines, "\n")
        local src = ariadne.Source.new(code)
        lu.assertEquals(#src, #lines)
        local chars, bytes = 0, 0
        for i, line in ipairs(lines) do
            lu.assertEquals(src[i].offset, chars + 1)
            lu.assertEquals(src[i].byte_offset, bytes + 1)
            lu.assertEquals(get_line_text(src, src[i]), line)
            chars = chars + utf8.len(line) + 1
            bytes = bytes + #line + 1
        end
    end

    function TestSource.test_empty()
        test_with_lines { "" }
    end

    function TestSource.test_single()
        test_with_lines { "single line" }
        test_with_lines { "single line with CR\r" }
    end

    function TestSource.test_multiple()
        test_with_lines {
            "first line",
            "second line",
            "third line",
        }
        test_with_lines {
            "line with あ unicode",
            "another line with emoji 😊",
            "final line",
        }
    end

    function TestSource.test_trims_trailing_space()
        test_with_lines {
            "Trailing spaces    ",
            "not trimmed\t",
        }
    end

    function TestSource.test_various_line_endings()
        test_with_lines {
            "CR\r",
            "VT\x0B",
            "FF\x0C",
            "NEL\u{0085}",
            "LS\u{2028}",
            "PS\u{2029}",
        }
    end
end

local TestColor = {}
do
    function TestColor.test_colors()
        local gen = ariadne.ColorGenerator.new()
        local colors = {}
        colors[#colors + 1] = gen:next()
        colors[#colors + 1] = gen:next()
        colors[#colors + 1] = gen:next()
        lu.assertNotEquals(colors[1], colors[2])
        lu.assertNotEquals(colors[2], colors[3])
        lu.assertNotEquals(colors[1], colors[3])
    end
end

local TestWrite = {}
do
    ---@param index_type? "byte"|"char"
    ---@param compact? boolean
    ---@return Config
    local function no_color_ascii(index_type, compact)
        return ariadne.Config.new {
            color = false,
            char_set = ariadne.Characters.ascii,
            index_type = index_type,
            compact = compact,
        }
    end

    function TestWrite.test_one_message()
        local msg = remove_trailing(
            ariadne.Report.build("Error", 0)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :render(ariadne.Source.new(""))
        )

        lu.assertEquals(msg, ([=[
Error: can't compare apples with oranges
]=]))
    end

    function TestWrite.test_two_labels_without_messages()
        local text = "apple == orange;"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5))
            :with_label(ariadne.Label.new(10, 15))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 |     alpha
   |     ^^|^^
   |       `---- This is an apple
 2 | ,-> bravo
 3 | |-> charlie
   | |
   | `------------- This is an orange
---'
]=]))
    end

    function TestWrite.test_two_labels_with_messages_compact()
        local text = "apple == orange;"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii(nil, true))
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii "char")
            :with_message("can't compare äpplës with örängës")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an äpplë"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an örängë"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii "byte")
            :with_message("can't compare äpplës with örängës")
            :with_label(ariadne.Label.new(1, 7):with_message("This is an äpplë"))
            :with_label(ariadne.Label.new(12, 20):with_message("This is an örängë"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 12)
            :with_config(no_color_ascii "byte")
            :with_message("can't compare äpplës with örängës")
            :with_label(ariadne.Label.new(1, 7):with_message("This is an äpplë"))
            :with_label(ariadne.Label.new(12, 20):with_message("This is an örängë"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(#text - 5, #text):with_message("This is an orange"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii "byte")
            :with_message("unexpected end of file")
            :with_label(ariadne.Label.new(9):with_message("Unexpected end of file"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: unexpected end of file
   ,-[ <unknown>:1:1 ]
   |
 1 | apple ==
   |         |
   |         `- Unexpected end of file
---'
]=]))
    end

    function TestWrite.test_empty_input()
        local text = ""
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("unexpected end of file")
            :with_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("unexpected end of file")
            :with_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :with_help("have you tried going to the farmer's market?")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("unexpected end of file")
            :with_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :with_note("eat your greens!")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("unexpected end of file")
            :with_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :with_note("eat your greens!")
            :with_help("have you tried going to the farmer's market?")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
                    return ariadne.Report.build("Error", 1)
                        :with_config(no_color_ascii "byte")
                        :with_message("Label")
                        :with_label(ariadne.Label.new(i, j):with_message("Label"))
                        :render(ariadne.Source.new(text))
                end)
                lu.assertTrue(ok)
                lu.assertEquals(type(result), "string")
            end
        end
    end

    function TestWrite.test_multiline_label()
        local text = "apple\n==\norange"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_label(ariadne.Label.new(1, #text):with_message("illegal comparison"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_label(ariadne.Label.new(1, #text):with_message("URL"))
            :with_label(ariadne.Label.new(1, colon_start):with_message("scheme"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(1, 5):with_message("Have I mentioned that this is an apple?"))
            :with_label(ariadne.Label.new(1, 5):with_message("No really, have I mentioned that?"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :with_label(ariadne.Label.new(10, 15):with_message("Have I mentioned that this is an orange?"))
            :with_label(ariadne.Label.new(10, 15):with_message("No really, have I mentioned that?"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :with_note("stop trying ... this is a fruitless endeavor")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii(nil, true))
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :with_note("stop trying ... this is a fruitless endeavor")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :with_help("have you tried peeling the orange?")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :with_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :with_help("have you tried peeling the orange?")
            :with_note("stop trying ... this is a fruitless endeavor")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :with_note("No need to try, they can't be compared.")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :with_note("No need to try, they can't be compared.")
            :with_note("Yeah, really, please stop.")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :with_note("No need to try, they can't be compared.")
            :with_note("Yeah, really, please stop.\nIt has no resemblance.")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Advice", 1)
            :with_config(no_color_ascii())
            :with_message("can't compare apples with oranges")
            :with_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :with_help("No need to try, they can't be compared.")
            :with_help("Yeah, really, please stop.\nIt has no resemblance.")
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("line offset demo")
            :with_label(ariadne.Label.new(12, 22):with_message("Second line"))
            :render(ariadne.Source.new(text, nil, 9))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("ordered labels")
            :with_label(ariadne.Label.new(1, 3):with_message("Left"))
            :with_label(ariadne.Label.new(4, 6):with_order(-10):with_message("Right"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("gaps between labels")
            :with_label(ariadne.Label.new(1, 5):with_message("first"))
            :with_label(ariadne.Label.new(13, 19):with_message("third"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Error", 3)
            :with_config(cfg)
            :with_message("zero length span")
            :with_label(ariadne.Label.new(3, 2):with_message("point"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: zero length span
   ,-[ <unknown>:1:3 ]
   |
 1 | delta
   |   |
   |   `- point
---'
]=]))
    end

    function TestWrite.test_priority_highlight_and_color()
        local text = "klmnop"
        local strong = ariadne.Label.new(2, 5):with_message("strong"):with_priority(10):with_color(
            function(k)
                if k == "reset" then return "]" end
                return "["
            end)
        local weak = ariadne.Label.new(1, 4):with_message("weak")
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("overlap priorities")
            :with_label(weak)
            :with_label(strong)
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: overlap priorities
   ,-[ <unknown>:1:1 ]
   |
 1 | k[lmno]p
   | ^[^]|[|^]
   |   `[-]--- weak
   |    [|]
   |    [`---] strong
---'
]=]))
    end

    function TestWrite.test_multiple_arrow_connectors()
        local text = "qrstuvwx"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("stacked arrows")
            :with_label(ariadne.Label.new(1, 3):with_message("left"))
            :with_label(ariadne.Label.new(5, 8):with_message("right"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
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
            ariadne.Report.build("Notice", 1)
            :with_config(no_color_ascii())
            :with_code("E100")
            :with_message("custom kind")
            :render(ariadne.Source.new("x"))
        )

        lu.assertEquals(msg, ([=[
[E100] Notice: custom kind
]=]))
    end

    function TestWrite.test_warning_and_advice()
        local warning = remove_trailing(
            ariadne.Report.build("Warning", 1)
            :with_config(no_color_ascii())
            :with_message("careful")
            :render(ariadne.Source.new("w"))
        )
        local advice = remove_trailing(
            ariadne.Report.build("Advice", 1)
            :with_config(no_color_ascii())
            :with_message("consider")
            :render(ariadne.Source.new("a"))
        )

        lu.assertEquals(warning, ([=[
Warning: careful
]=]))
        lu.assertEquals(advice, ([=[
Advice: consider
]=]))
    end

    function TestWrite.test_byte_index_out_of_bounds()
        local cfg = no_color_ascii("byte")
        local msg = remove_trailing(
            ariadne.Report.build("Error", 100)
            :with_config(cfg)
            :with_message("unknown position")
            :render(ariadne.Source.new("hi"))
        )

        lu.assertEquals(msg, ([=[
Error: unknown position
]=]))
    end

    function TestWrite.test_invalid_label_skipped()
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("invalid label")
            :with_label(ariadne.Label.new(999, 1000):with_message("ignored"))
            :render(ariadne.Source.new("short"))
        )

        lu.assertEquals(msg, ([=[
Error: invalid label
]=]))
    end

    -- Additional coverage-focused tests (expected outputs intentionally left blank)
    function TestWrite.test_oob_location_with_label_byte()
        local text = "hi"
        local cfg = no_color_ascii("byte")
        local msg = remove_trailing(
            ariadne.Report.build("Error", 100)
            :with_config(cfg)
            :with_message("oob location with label")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: oob location with label
   ,-[ <unknown>:?:? ]
   |
 1 | hi
   | |
   | `-- label
---'
]=]))
    end

    function TestWrite.test_multiline_sort_and_padding()
        -- First line has trailing spaces to exercise split_at_column padding; two
        -- multiline labels with messages ensure sorting comparators run.
        local text = "abc   \nmid\nxyz"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("multiline sort & padding")
            :with_label(ariadne.Label.new(5, 13):with_message("outer")) -- from trailing spaces into last line
            :with_label(ariadne.Label.new(9, 13):with_message("inner")) -- spans mid->x
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: multiline sort & padding
   ,-[ <unknown>:1:1 ]
   |
 1 | ,---> abc
 2 | | ,-> mid
 3 | | |-> xyz
   | | |    ^
   | | `-------- inner
   | |      |
   | `------^--- outer
---'
]=]))
    end

    function TestWrite.test_pointer_and_connectors()
        -- On the second line we have both a multiline end and an inline label with
        -- messages, which drives connector rows and vbar cells.
        local text = "abcde\nfghij\n"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii())
            :with_message("pointer and connectors")
            :with_label(ariadne.Label.new(2, 8):with_message("multi")) -- multi spanning line1->line2
            :with_label(ariadne.Label.new(9, 10):with_message("inline"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, ([=[
Error: pointer and connectors
   ,-[ <unknown>:1:1 ]
   |
 1 | ,-> abcde
 2 | |-> fghij
   | |     ^|
   | `----------- multi
   |        |
   |        `---- inline
---'
]=]))
    end

    function TestWrite.test_demo()
        local text = [[
def five = match () in {
	() => 5,
	() => "5",
}

def six =
    five
    + 1
]]

        local msg = remove_trailing(
            ariadne.Report.build("Error", 12)
            :with_config(no_color_ascii())
            :with_code "3"
            :with_message("Incompatible types")
            :with_label(ariadne.Label.new(33, 33):with_message("This is of type Nat"))
            :with_label(ariadne.Label.new(43, 45):with_message("This is of type Str"))
            :with_label(ariadne.Label.new(12, 48):with_message("This values are outputs of this match expression"))
            :with_label(ariadne.Label.new(1, 48):with_message("The definition has a problem"))
            :with_label(ariadne.Label.new(51, 76):with_message("Usage of definition here"))
            :with_note("Outputs of match expressions must coerce to the same type")
            :render(ariadne.Source.new(text, "sample.tao"))
        )

        lu.assertEquals(msg, [=[
[3] Error: Incompatible types
   ,-[ sample.tao:1:12 ]
   |
 1 | ,-----> def five = match () in {
   | |                  ^
   | | ,----------------'
 2 | | |         () => 5,
   | | |               |
   | | |               `-- This is of type Nat
 3 | | |         () => "5",
   | | |               ^|^
   | | |                `--- This is of type Str
 4 | | |---> }
   | | |     ^
   | | `--------- This values are outputs of this match expression
   | |       |
   | `-------^--- The definition has a problem
   |
 6 |     ,-> def six =
   :     :
 8 |     |->     + 1
   |     |
   |     `------------- Usage of definition here
   |
   | Note: Outputs of match expressions must coerce to the same type
---'
]=])
    end

    -- Test 1: Multi-source groups (line 1529)
    function TestWrite.test_multi_source_groups()
        local src1 = ariadne.Source.new("apple", "file1.lua")
        local src2 = ariadne.Source.new("orange", "file2.lua")
        local cache = ariadne.Cache.new()
        cache["file1.lua"] = src1
        cache["file2.lua"] = src2

        local msg = remove_trailing(ariadne.Report.build("Error", 1, "file1.lua")
            :with_config(no_color_ascii())
            :with_message("cross-file error")
            :with_label(ariadne.Label.new(1, 5, "file1.lua"))
            :with_label(ariadne.Label.new(1, 6, "file2.lua"))
            :render(cache))
        lu.assertEquals(msg, [[
Error: cross-file error
   ,-[ file1.lua:1:1 ]
   |
 1 | apple
   |
   |-[ file2.lua:1:1 ]
   |
 1 | orange
---'
]])
    end

    -- Test 2: Compact mode with multiline arrows (line 1413)
    function TestWrite.test_compact_multiline_arrows()
        local cfg = no_color_ascii()
        cfg.compact = true
        cfg.multiline_arrows = true
        local src = ariadne.Source.new("apple\norange\nbanana")
        local msg = ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("multiline span")
            :with_label(ariadne.Label.new(1, 12):with_message("crosses lines"))
            :render(src)
        lu.assertEquals(msg, [=[
Error: multiline span
   ,-[ <unknown>:1:1 ]
 1 |,>apple
 2 ||>orange
   |`--------- crosses lines
]=])
    end

    -- Test 3: cross_gap disabled (line 1409)
    function TestWrite.test_cross_gap_disabled()
        local cfg = no_color_ascii()
        cfg.cross_gap = false
        local src = ariadne.Source.new("apple\norange\nbanana\ngrape")
        local msg = ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test cross_gap")
            :with_label(ariadne.Label.new(1, 19):with_message("span 1"))
            :with_label(ariadne.Label.new(21, 25):with_message("span 2"))
            :render(src)
        lu.assertEquals(msg, "Error: test cross_gap\
   ,-[ <unknown>:1:1 ]\
   |\
 1 | ,-> apple\
   : :   \
 3 | |-> banana\
   | |            \
   | `------------ span 1\
 4 |     grape\
   |     ^^|^^  \
   |       `---- span 2\
---'\
")
    end

    -- Test 4: default_color for "error" and "skipped_margin" (lines 238-244)
    function TestWrite.test_default_color_categories()
        local cfg = ariadne.Config.new {
            char_set = ariadne.Characters.ascii,
        }
        local src = ariadne.Source.new("apple\n\n\norange")
        local msg = ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test default colors")
            :with_label(ariadne.Label.new(1, 6):with_message("spans multiple lines"))
            :with_note("note with default colors")
            :render(src)
        -- Expected: "Error:" in red, skipped margin ":" in dim gray
        msg = ("%q"):format(msg)
        lu.assertEquals(msg, [[
"\27[31mError:\27[0m test default colors\
   \27[38;5;246m,-[\27[0m <unknown>:1:1 \27[38;5;246m]\27[0m\
   \27[38;5;246m|\27[0m\
 \27[38;5;246m1 |\27[0m \27[38;5;249mapple\27[0m\
   \27[38;5;240m| \27[0m\27[39m^^^|^^\27[0m  \
   \27[38;5;240m| \27[0m   \27[39m`----\27[0m spans multiple lines\
   \27[38;5;240m| \
   | \27[0m\27[38;5;115mNote: note with default colors\
\27[0m\27[38;5;246m---'\27[0m\
"]])

        msg = ("%q"):format(remove_trailing(
            ariadne.Report.build("Advice", 1)
            :with_config(cfg)
            :with_message("test default colors")
            :render(src)
        ))
        lu.assertEquals(msg, [[
"\27[38;5;147mAdvice:\27[0m test default colors\
"]])

        msg = ("%q"):format(remove_trailing(
            ariadne.Report.build("Warning", 1)
            :with_config(cfg)
            :with_message("test default colors")
            :render(src)
        ))
        lu.assertEquals(msg, [[
"\27[33mWarning:\27[0m test default colors\
"]])
    end -- Test 2: Compact mode with multiline arrows (line 1413)

    function TestWrite.test_compact_multiline_arrows()
        local cfg = no_color_ascii()
        cfg.compact = true
        cfg.multiline_arrows = true
        local src = ariadne.Source.new("apple\norange\nbanana")
        local msg = ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("multiline span")
            :with_label(ariadne.Label.new(1, 12):with_message("crosses lines"))
            :render(src)
        lu.assertEquals(msg, [=[
Error: multiline span
   ,-[ <unknown>:1:1 ]
 1 |,>apple
 2 ||>orange
   |`--------- crosses lines
]=])
    end

    -- Test 3: cross_gap disabled (line 1409)
    function TestWrite.test_cross_gap_disabled()
        local cfg = no_color_ascii()
        cfg.cross_gap = false
        local src = ariadne.Source.new("apple\norange\nbanana\ngrape")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test cross_gap")
            :with_label(ariadne.Label.new(1, 19):with_message("span 1"))
            :with_label(ariadne.Label.new(21, 25):with_message("span 2"))
            :render(src))
        lu.assertEquals(msg, [[
Error: test cross_gap
   ,-[ <unknown>:1:1 ]
   |
 1 | ,-> apple
   : :
 3 | |-> banana
   | |
   | `------------ span 1
 4 |     grape
   |     ^^|^^
   |       `---- span 2
---'
]])
    end

    -- Test 5: underlines disabled (line 1204)
    function TestWrite.test_underlines_disabled()
        local cfg = no_color_ascii()
        cfg.underlines = false
        local src = ariadne.Source.new("apple orange")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("no underlines")
            :with_label(ariadne.Label.new(1, 5):with_message("label"))
            :render(src))
        lu.assertEquals(msg, [[
Error: no underlines
   ,-[ <unknown>:1:1 ]
   |
 1 | apple orange
   |   |
   |   `---- label
---'
]])
    end

    -- Test 6: overlapping underlines with shorter label (line 1216)
    function TestWrite.test_underline_shorter_label_priority()
        local cfg = no_color_ascii()
        cfg.underlines = true
        local src = ariadne.Source.new("apple orange banana")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("overlapping same priority")
            -- Add shorter label first, then longer - to ensure ll_len < res_len triggers
            :with_label(ariadne.Label.new(3, 7):with_message("short"):with_priority(1))
            :with_label(ariadne.Label.new(4, 7):with_message("short2"):with_priority(1))
            :with_label(ariadne.Label.new(1, 10):with_message("long"):with_priority(1))
            :render(src))
        -- The shorter label should win when priority is the same
        lu.assertEquals(msg, [[
Error: overlapping same priority
   ,-[ <unknown>:1:1 ]
   |
 1 | apple orange banana
   | ^^^^||^^^^
   |     `------- short
   |      |
   |      `------ short2
   |      |
   |      `------ long
---'
]])
    end

    -- Test 8: compact multiline with uarrow (line 1349)
    function TestWrite.test_compact_multiline_uarrow()
        local cfg = no_color_ascii()
        cfg.compact = true
        cfg.multiline_arrows = true
        local src = ariadne.Source.new("apple\norange\nbanana")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("compact uarrow")
            :with_label(ariadne.Label.new(1, 12):with_message("multiline"))
            :render(src))
        lu.assertEquals(msg, [[
Error: compact uarrow
   ,-[ <unknown>:1:1 ]
 1 |,>apple
 2 ||>orange
   |`--------- multiline
]])
    end

    -- Test 9: cross_gap disabled (based on test_pointer_and_connectors)
    function TestWrite.test_cross_gap_vbar_hbar()
        local cfg = no_color_ascii()
        cfg.cross_gap = false
        -- Based on test_pointer_and_connectors but with cross_gap disabled
        local text = "abcde\nfghij\n"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("xbar test")
            :with_label(ariadne.Label.new(2, 8):with_message("multi"))
            :with_label(ariadne.Label.new(9, 10):with_message("inline"))
            :render(ariadne.Source.new(text))
        )
        -- With cross_gap=false, we should see '+' in the message connector line
        lu.assertEquals(msg, [[
Error: xbar test
   ,-[ <unknown>:1:1 ]
   |
 1 | ,-> abcde
 2 | |-> fghij
   | |     ^|
   | `------+---- multi
   |        |
   |        `---- inline
---'
]])
    end

    -- Test 10: compact mode with two multiline labels triggering uarrow
    function TestWrite.test_compact_two_multiline_uarrow()
        local cfg = no_color_ascii()
        cfg.compact = true
        -- Two multiline labels: one starts earlier, one starts later on line 1
        -- This should trigger the uarrow condition at line 1343
        local src = ariadne.Source.new("abcdefgh\nijklmnop\nqrstuvwx")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("two multiline labels")
            :with_label(ariadne.Label.new(1, 18):with_message("outer"))
            :with_label(ariadne.Label.new(3, 19):with_message("inner"))
            :render(src))
        lu.assertEquals(msg, [[
Error: two multiline labels
   ,-[ <unknown>:1:1 ]
 1 |,->abcdefgh
   ||,---'
 2 ||->ijklmnop
   |`------------ outer
 3 | |>qrstuvwx
   | `---------- inner
]])
    end

    -- Test 11: compact mode with two multiline labels ending at same col (line 1340)
    function TestWrite.test_compact_multiline_same_end_col()
        local cfg = no_color_ascii()
        cfg.compact = true
        -- Two multiline labels both ending at the same column
        -- This triggers the uarrow at line 1340
        -- labelA: char 1-6 (line 1 col 1 to line 2 col 1)
        -- labelB: char 2-6 (line 1 col 2 to line 2 col 1)
        local src = ariadne.Source.new("abcd\nefgh\nijkl\n")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test two multiline labels ending at same col")
            :with_label(ariadne.Label.new(1, 6):with_message("labelA spans 1-6"))
            :with_label(ariadne.Label.new(2, 6):with_message("labelB spans 2-6"))
            :render(src))
        lu.assertEquals(msg, [[
Error: test two multiline labels ending at same col
   ,-[ <unknown>:1:1 ]
 1 |,->abcd
   ||,--'
 2 |||>efgh
   ||`------- labelB spans 2-6
   |`--^----- labelA spans 1-6
]])
    end

    function TestWrite.test_uarrow()
        local src = ariadne.Source.new("apple\norange\nbanana")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(no_color_ascii(nil, true))
            :with_message("uarrow test")
            :with_label(ariadne.Label.new(1, 7):with_message("inner"))
            :with_label(ariadne.Label.new(2, 14):with_message("outer"):with_order(1))
            :with_label(ariadne.Label.new(1, 8):with_message("outer outer"):with_order(2))
            :render(src))
        lu.assertEquals(msg, [=[
Error: uarrow test
   ,-[ <unknown>:1:1 ]
 1 | ,->apple
   | |,-'^
   |,----'
 2 ||||>orange
   |||`--------- inner
   ||`---^------ outer outer
 3 ||-->banana
   |`---------- outer
]=])
    end

    function TestWrite.test_margin_xbar()
        local cfg = no_color_ascii()
        cfg.cross_gap = false
        local src = ariadne.Source.new("apple\norange\nbanana\nstrawberry")
        local msg = remove_trailing(ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("margin xbar test")
            :with_label(ariadne.Label.new(1, 14):with_message("outer"):with_order(0))
            :with_label(ariadne.Label.new(7, 21):with_message("inner"):with_order(1))
            :render(src))
        lu.assertEquals(msg, [[
Error: margin xbar test
   ,-[ <unknown>:1:1 ]
   |
 1 |   ,-> apple
 2 | ,-+-> orange
 3 | | |-> banana
   | | |
   | | `------------ outer
 4 | |---> strawberry
   | |
   | `----------------- inner
---'
]])
    end
end

--- Helper function for tests that need line_width
---@param line_width? integer
---@param index_type? "byte"|"char"
---@param compact? boolean
---@return Config
local function no_color_ascii_width(line_width, index_type, compact)
    return ariadne.Config.new {
        color = false,
        char_set = ariadne.Characters.ascii,
        index_type = index_type,
        compact = compact,
        line_width = line_width,
    }
end

local TestLineWidth = {}
do
    -- Phase 1: Header Truncation Tests (MVP: simple suffix truncation)
    -- Header format: "   ,-[ {path}:{line}:{col} ]"
    -- Fixed width = 7 (before) + 2 (after) = 9 chars
    -- Available for path:line:col = line_width - 9
    -- Ellipsis width = 3 (ASCII "...")
    -- Suffix width = available - 3

    function TestLineWidth.test_header_no_truncation_short_path()
        -- Path is short, no truncation needed
        local text = "apple"
        local cfg = no_color_ascii_width(60)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, "file.lua"))
        )
        lu.assertEquals(msg, [[
Error: test
   ,-[ file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_truncation_long_path()
        -- Path exceeds line_width, should truncate from start (keep suffix)
        -- Generate long path: ("dir/"):rep(20) = "dir/dir/.../dir/" (80 chars)
        local text = "apple"
        local cfg = no_color_ascii_width(40)
        local long_path = ("dir/"):rep(20) .. "file.lua"
        -- Full id: ("dir/"):rep(20) + "file.lua" = 80 + 8 = 88 chars
        -- line_width=40, line_no_width=1, loc="1:1"(3 chars)
        -- fixed_width = 1 + 9 + 3 = 13
        -- avail = 40 - 13 - 3(ellipsis) = 24
        -- Expected id: "..." + 24 chars suffix = ".../dir/dir/dir/dir/file.lua" (28 total)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, long_path))
        )
        lu.assertEquals(msg, [[
Error: test
   ,-[ ...dir/dir/dir/dir/file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_truncation_large_line_number()
        -- Generate a file with many lines to test large line numbers
        -- Use ("line\n"):rep(200) instead of manual loop
        local text = ("line\n"):rep(200) .. "target"
        local cfg = no_color_ascii_width(45)
        local long_path = ("dir/"):rep(20) .. "file.lua"

        -- Line 201 is the "target" line, char position = 200*5 + 1 = 1001
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1001)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1001, 1001):with_message("label"))
            :render(ariadne.Source.new(text, long_path))
        )
        -- Available = 45 - 9 - 3 = 33, loc = 5, ellipsis = 3, suffix = 25
        -- Expected: ".../dir/dir/dir/dir/file.lua" (25 chars fits)
        lu.assertEquals(msg, [[
Error: test
     ,-[ .../dir/dir/dir/dir/file.lua:201:1 ]
     |
 201 | target
     | |
     | `-- label
-----'
]])
    end

    function TestLineWidth.test_header_truncation_utf8_path()
        -- Path with UTF-8 characters (CJK chars are width 2)
        -- "目录" = 4 display width, repeat 20 times = 80 display width
        local text = "apple"
        local cfg = no_color_ascii_width(40)
        local utf8_path = ("目录/"):rep(20) .. "文件.lua"
        -- Display width of id: 20*(2+2+1) + (2+2+4) = 100 + 9 = 109 width units
        -- (目=2, 录=2, /=1) * 20 + (文=2, 件=2, .lua=4)
        -- line_width=40, line_no_width=1, loc="1:1"(3 chars)
        -- fixed_width = 1 + 9 + 3 = 13
        -- avail = 40 - 13 - 3(ellipsis "..." is 3 width in ascii mode) = 24
        -- Expected: "..." + suffix to fit 24 width = ".../目录/目录/目录/文件.lua"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, utf8_path))
        )
        lu.assertEquals(msg, [[
Error: test
   ,-[ .../目录/目录/目录/文件.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_truncation_tab_in_path()
        -- Path contains tab character (should normalize to spaces before width calc)
        -- Tab width = 4 (default)
        local text = "apple"
        local cfg = no_color_ascii_width(40)
        local tab_path = ("dir\t"):rep(20) .. "file.lua"
        -- Tab normalized to single space: "dir " * 20 + "file.lua" = 80 + 8 = 88 chars
        -- line_width=40, line_no_width=1, loc="1:1"(3 chars)
        -- fixed_width = 1 + 9 + 3 = 13
        -- avail = 40 - 13 - 3(ellipsis) = 24
        -- Expected: "..." + 24 chars suffix = "...dir dir dir dir file.lua"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, tab_path))
        )
        -- Expected: tabs normalized to spaces, then suffix truncated
        -- "...dir    file.lua:1:1" (approx 22 chars)
        lu.assertEquals(msg, [[
Error: test
   ,-[ ...dir dir dir dir file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_truncation_very_narrow()
        -- Very narrow line_width: available = 25 - 9 = 16
        local text = "apple"
        local cfg = no_color_ascii_width(25)
        local long_path = ("dir/"):rep(20) .. "file.lua"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, long_path))
        )
        -- Available = 25 - 9 - 1 = 15, loc = 3, ellipsis = 3, suffix = 9
        -- "/file.lua" = 9 chars, fits
        lu.assertEquals(msg, [[
Error: test
   ,-[ .../file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_no_truncation_when_nil()
        -- line_width = nil, no truncation should occur
        local text = "apple"
        local cfg = no_color_ascii_width(nil)
        local long_path = ("dir/"):rep(20) .. "file.lua"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, long_path))
        )
        -- Full path should be displayed (80 chars total)
        local expected_header = ",-[ " .. long_path .. ":1:1 ]"
        lu.assertEquals(msg, [[
Error: test
   ]] .. expected_header .. [[

   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_truncation_exact_boundary()
        -- Path exactly matches available width, no truncation
        local text = "apple"
        local cfg = no_color_ascii_width(30)
        -- line_width=30, line_no_width=1, loc="1:1"(3 chars)
        -- fixed_width = 1 + 9 + 3 = 13
        -- id="short/path.lua" = 14 chars, total = 13 + 14 + 3 = 30, exactly fits
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, "short/path.lua"))
        )
        -- "short/path.lua:1:1" = 18 chars, under 21, no truncation
        lu.assertEquals(msg, [[
Error: test
   ,-[ short/path.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end

    function TestLineWidth.test_header_truncation_one_over_boundary()
        -- Path exceeds available width by exactly 1 char
        local text = "apple"
        local cfg = no_color_ascii_width(30)
        -- Full id: "xxx...xxx.lua" = 15 + 4 = 19 chars
        -- line_width=30, line_no_width=1, loc="1:1"(3 chars)
        -- fixed_width = 1 + 9 + 3 = 13
        -- avail = 30 - 13 - 3(ellipsis) = 14
        -- Expected: "..." + 14 chars suffix = "...xxxxxxxxxx.lua" (17 total, with :1:1 = 22 total)
        local long_name = ("x"):rep(15) .. ".lua"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 1):with_message("label"))
            :render(ariadne.Source.new(text, long_name))
        )
        -- Expected suffix: last 18 chars of "xxxxxxxxxxxxxxx.lua:1:1" = "xxxxxxxxxx.lua:1:1"
        lu.assertEquals(msg, [[
Error: test
   ,-[ ...xxxxxxxxxx.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
    end
end

TestLineWindowing = {}
do
    function TestLineWindowing.test_single_label_at_end_of_long_line()
        -- Label at the very end of a 900+ char line
        -- Should show ellipsis prefix + local context
        local text = string.rep("apple == ", 100) .. "orange"
        -- Total length: 100*9 + 6 = 906 chars
        -- Label is at chars 901-906 ("orange")
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(901, 906):with_message("This is an orange"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:1 ]
   |
 1 | ... apple == apple == apple == apple == apple == orange
   |                                                  ^^^|^^
   |                                                     `---- This is an orange
---'
]])
    end

    function TestLineWindowing.test_single_label_in_middle_of_long_line()
        -- Label in the middle of a long line
        -- Should center the label in the available width
        local prefix = string.rep("a", 400)
        local target = "error"
        local suffix = string.rep("b", 400)
        local text = prefix .. target .. suffix
        -- Total: 805 chars, label at 401-405
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 401)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(401, 405):with_message("found here"))
            :render(ariadne.Source.new(text))
        )

        -- Available for content = 80 - 5 = 75
        -- With ellipsis: 72 chars of content
        -- Label is 5 chars wide, at position 401-405
        -- Ideally center the label: show some context before and after
        -- Could show chars ~370-441 (72 chars centered around 401-405)
        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:401 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |                              ^^|^^
   |                                `---- found here
---'
]])
    end

    function TestLineWindowing.test_small_msg()
        local text = ("a"):rep(400) .. "error" .. ("b"):rep(400)
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 401)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(401, 405):with_message("1"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:401 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |                                  ^^|^^
   |                                    `---- 1
---'
]])
    end

    function TestLineWindowing.test_minimum_line_width()
        -- Label at the start of a long line
        -- Should NOT show ellipsis, just truncate the end
        local text = ("a"):rep(400) .. "error" .. ("b"):rep(400)
        local msg = "a very long message that exceeds the line width significantly"
        local cfg = no_color_ascii_width(10)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 401)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(401, 405):with_message(msg))
            :render(ariadne.Source.new(text))
        )

        -- Label is at the start, so skip_chars = 0
        -- Just show first 75 chars (no ellipsis needed)
        lu.assertEquals(msg, [[
Error: test
   ,-[ ...unknown>:1:401 ]
   |
 1 | ...errorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |    ^^|^^
   |      `---- a very long message that exceeds the line width significantly
---'
]])
    end

    function TestLineWindowing.test_fit_line_width()
        -- Label at the start of a long line
        -- Should NOT show ellipsis, just truncate the end
        local text = ("a"):rep(55) .. "error" .. ("b"):rep(16)
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 401)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(56, 60):with_message "at start")
            :render(ariadne.Source.new(text))
        )

        -- Label is at the start, so skip_chars = 0
        -- Just show first 75 chars (no ellipsis needed)
        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:401 ]
   |
 1 | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbb...
   |                                                        ^^|^^
   |                                                          `---- at start
---'
]])
    end

    function TestLineWindowing.test_single_label_at_start_of_long_line()
        -- Label at the start of a long line
        -- Should NOT show ellipsis, just truncate the end
        local text = "error" .. string.rep("x", 900)
        -- Label at 1-5
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(1, 5):with_message("at start"))
            :render(ariadne.Source.new(text))
        )

        -- Label is at the start, so skip_chars = 0
        -- Just show first 75 chars (no ellipsis needed)
        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:1 ]
   |
 1 | errorxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx...
   | ^^|^^
   |   `---- at start
---'
]])
    end

    function TestLineWindowing.test_no_windowing_when_line_fits()
        -- Line is short enough to fit within line_width
        -- Should NOT apply windowing
        local text = "short line with error"
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 17)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(17, 21):with_message("here"))
            :render(ariadne.Source.new(text))
        )

        -- Line is only 21 chars, fits easily in 75 available
        -- No windowing needed
        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:17 ]
   |
 1 | short line with error
   |                 ^^|^^
   |                   `---- here
---'
]])
    end

    function TestLineWindowing.test_no_windowing_when_line_width_nil()
        -- line_width = nil, should display full line
        local text = string.rep("a", 200)
        local cfg = no_color_ascii_width(nil)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 195)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(195, 200):with_message("end"))
            :render(ariadne.Source.new(text))
        )

        -- Full line should be displayed (200 chars)
        local expected_line = " 1 | " .. text
        lu.assertTrue(msg:find(expected_line, 1, true) ~= nil, "Should show full line")
    end

    function TestLineWindowing.test_multiple_labels_on_long_line()
        -- Multiple labels on same long line
        -- Should window based on leftmost label (min_col)
        local prefix = string.rep("a", 100)
        local label1 = "error"
        local middle = string.rep("b", 200)
        local label2 = "warn"
        local suffix = string.rep("c", 300)
        local text = prefix .. label1 .. middle .. label2 .. suffix
        -- Total: 609 chars
        -- label1: 101-105, label2: 306-309
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 101)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(101, 105):with_message("first error"))
            :with_label(ariadne.Label.new(306, 309):with_message("second warning"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:101 ]
   |
 1 | ...errorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbwarncccccccccccccc...
   |    ^^|^^                                                                                                                                                                                                        ^^|^
   |      `---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- first error
   |                                                                                                                                                                                                                   |
   |                                                                                                                                                                                                                   `--- second warning
---'
]])
    end

    function TestLineWindowing.test_cjk_characters_in_line()
        -- Line with CJK characters (width 2 each)
        -- Should correctly calculate display width
        local text = string.rep("中", 50) .. "错误" .. string.rep("文", 50)
        -- Total: 102 CJK chars = 204 display width
        -- Label "错误" at position 51-52 (2 chars, 4 display width)
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 51)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(51, 52):with_message("这是错误"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:51 ]
   |
 1 | ...中中中中中中中中中中中中中错误文文文文文文文文文文文文文文文文文文文...
   |                              ^^|^
   |                                `----- 这是错误
---'
]])
    end

    function TestLineWindowing.test_mixed_ascii_cjk_characters()
        -- Mixed ASCII and CJK characters
        -- ASCII width 1, CJK width 2
        local prefix = string.rep("a", 200)
        local text = prefix .. "hello世界error错误test"
        -- Label on "error错误" (5 ASCII + 2 CJK = 7 chars)
        -- Position: 201-207 (char positions)
        local cfg = no_color_ascii_width(80)
        local msg = remove_trailing(
            ariadne.Report.build("Error", 201)
            :with_config(cfg)
            :with_message("test")
            :with_label(ariadne.Label.new(206, 212):with_message("mixed error"))
            :render(ariadne.Source.new(text))
        )

        lu.assertEquals(msg, [[
Error: test
   ,-[ <unknown>:1:201 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaahello世界error错误test
   |                                                   ^^^^^|^^^
   |                                                        `------- mixed error
---'
]])
    end
end

_G.TestSource = TestSource
_G.TestColor = TestColor
_G.TestWrite = TestWrite
_G.TestLineWidth = TestLineWidth
_G.TestLineWindowing = TestLineWindowing

os.exit(lu.LuaUnit.run())
