local lu = require "luaunit"
local ariadne = require "ariadne_new"

local TestSource = {} do
    local function get_line_text(src, line)
        return src.text:sub(line:byte_span())
    end

    local function test_with_lines(lines)
        local code = table.concat(lines, "\n")
        local src = ariadne.Source.new(code)
        lu.assertEquals(#src, #lines)
        local chars, bytes = 0, 0
        for i, line in ipairs(lines) do
            lu.assertEquals(src[i].offset, chars+1)
            lu.assertEquals(src[i].byte_offset, bytes+1)
            lu.assertEquals(src[i].len, utf8.len(line))
            lu.assertEquals(src[i].byte_len, #line)
            lu.assertEquals(get_line_text(src, src[i]), line)
            chars = chars + utf8.len(line) + 1
            bytes = bytes + #line + 1
        end
        lu.assertEquals(src.len, chars - 1)
        lu.assertEquals(src.byte_len, bytes - 1)
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

local TestColor = {} do
    function TestColor.test_colors()
        local gen = ariadne.ColorGenerator.new()
        local colors = {}
        colors[#colors+1] = gen:next()
        colors[#colors+1] = gen:next()
        colors[#colors+1] = gen:next()
        lu.assertNotEquals(colors[1], colors[2])
        lu.assertNotEquals(colors[2], colors[3])
        lu.assertNotEquals(colors[1], colors[3])
    end
end

local TestWrite = {} do
    ---@param text string
    ---@return string
    local function remove_trailing(text)
        return (text:gsub("%s+\n", "\n"):gsub("%s+\n$", "\n"))
    end

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
            ariadne.Report.build("Error", 0, 0)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :render(ariadne.Source.new(""))
        )

        lu.assertEquals(msg, ([=[
Error: can't compare apples with oranges
]=]))
    end

    function TestWrite.test_two_labels_without_messages()
        local text = "apple == orange;"
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5))
            :add_label(ariadne.Label.new(10, 15))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii(nil, true))
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii "char")
            :set_message("can't compare äpplës with örängës")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an äpplë"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an örängë"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii "byte")
            :set_message("can't compare äpplës with örängës")
            :add_label(ariadne.Label.new(1, 7):with_message("This is an äpplë"))
            :add_label(ariadne.Label.new(12, 20):with_message("This is an örängë"))
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
            :set_message("can't compare äpplës with örängës")
            :add_label(ariadne.Label.new(1, 7):with_message("This is an äpplë"))
            :add_label(ariadne.Label.new(12, 20):with_message("This is an örängë"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(#text - 5, #text):with_message("This is an orange"))
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
            :set_message("unexpected end of file")
            :add_label(ariadne.Label.new(9):with_message("Unexpected end of file"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("unexpected end of file")
            :add_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("unexpected end of file")
            :add_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :add_help("have you tried going to the farmer's market?")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("unexpected end of file")
            :add_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :add_note("eat your greens!")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("unexpected end of file")
            :add_label(ariadne.Label.new(1, 0):with_message("No more fruit!"))
            :add_note("eat your greens!")
            :add_help("have you tried going to the farmer's market?")
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
                    return ariadne.Report.build("Error", 1, 1)
                        :with_config(no_color_ascii "byte")
                        :set_message("Label")
                        :add_label(ariadne.Label.new(i, j):with_message("Label"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :add_label(ariadne.Label.new(1, #text):with_message("illegal comparison"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :add_label(ariadne.Label.new(1, #text):with_message("URL"))
            :add_label(ariadne.Label.new(1, colon_start):with_message("scheme"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(1, 5):with_message("Have I mentioned that this is an apple?"))
            :add_label(ariadne.Label.new(1, 5):with_message("No really, have I mentioned that?"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :add_label(ariadne.Label.new(10, 15):with_message("Have I mentioned that this is an orange?"))
            :add_label(ariadne.Label.new(10, 15):with_message("No really, have I mentioned that?"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :add_note("stop trying ... this is a fruitless endeavor")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii(nil, true))
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :add_note("stop trying ... this is a fruitless endeavor")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :add_help("have you tried peeling the orange?")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
            :add_label(ariadne.Label.new(10, 15):with_message("This is an orange"))
            :add_help("have you tried peeling the orange?")
            :add_note("stop trying ... this is a fruitless endeavor")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :add_note("No need to try, they can't be compared.")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :add_note("No need to try, they can't be compared.")
            :add_note("Yeah, really, please stop.")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :add_note("No need to try, they can't be compared.")
            :add_note("Yeah, really, please stop.\nIt has no resemblance.")
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
            :set_message("can't compare apples with oranges")
            :add_label(ariadne.Label.new(1, 15):with_message("This is a strange comparison"))
            :add_help("No need to try, they can't be compared.")
            :add_help("Yeah, really, please stop.\nIt has no resemblance.")
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("line offset demo")
            :add_label(ariadne.Label.new(12, 22):with_message("Second line"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("ordered labels")
            :add_label(ariadne.Label.new(1, 3):with_message("Left"))
            :add_label(ariadne.Label.new(4, 6):with_order(-10):with_message("Right"))
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
            ariadne.Report.build("Error", 1, 15)
            :with_config(cfg)
            :set_message("gaps between labels")
            :add_label(ariadne.Label.new(1, 5):with_message("first"))
            :add_label(ariadne.Label.new(13, 19):with_message("third"))
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
            ariadne.Report.build("Error", 3, 2)
            :with_config(cfg)
            :set_message("zero length span")
            :add_label(ariadne.Label.new(3, 2):with_message("point"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("overlap priorities")
            :add_label(weak)
            :add_label(strong)
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("stacked arrows")
            :add_label(ariadne.Label.new(1, 3):with_message("left"))
            :add_label(ariadne.Label.new(5, 8):with_message("right"))
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
            :set_message("custom kind")
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
            :set_message("careful")
            :render(ariadne.Source.new("w"))
        )
        local advice = remove_trailing(
            ariadne.Report.build("Advice", 1)
            :with_config(no_color_ascii())
            :set_message("consider")
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
            ariadne.Report.build("Error", 100, 100)
            :with_config(cfg)
            :set_message("unknown position")
            :render(ariadne.Source.new("hi"))
        )

        lu.assertEquals(msg, ([=[
Error: unknown position
]=]))
    end

    function TestWrite.test_invalid_label_skipped()
        local msg = remove_trailing(
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("invalid label")
            :add_label(ariadne.Label.new(999, 1000):with_message("ignored"))
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
            ariadne.Report.build("Error", 100, 100)
            :with_config(cfg)
            :set_message("oob location with label")
            :add_label(ariadne.Label.new(1, 1):with_message("label"))
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("multiline sort & padding")
            :add_label(ariadne.Label.new(5, 13):with_message("outer")) -- from trailing spaces into last line
            :add_label(ariadne.Label.new(9, 13):with_message("inner")) -- spans mid->x
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
            ariadne.Report.build("Error", 1, 1)
            :with_config(no_color_ascii())
            :set_message("pointer and connectors")
            :add_label(ariadne.Label.new(2, 8):with_message("multi")) -- multi spanning line1->line2
            :add_label(ariadne.Label.new(9, 10):with_message("inline"))
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
            :set_message("Incompatible types")
            :add_label(ariadne.Label.new(33, 33):with_message("This is of type Nat"))
            :add_label(ariadne.Label.new(43, 45):with_message("This is of type Str"))
            :add_label(ariadne.Label.new(12, 48):with_message("This values are outputs of this match expression"))
            :add_label(ariadne.Label.new(1, 48):with_message("The definition has a problem"))
            :add_label(ariadne.Label.new(51, 76):with_message("Usage of definition here"))
            :add_note("Outputs of match expressions must coerce to the same type")
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
end

_G.TestSource = TestSource
_G.TestColor = TestColor
_G.TestWrite = TestWrite

os.exit(lu.LuaUnit.run())