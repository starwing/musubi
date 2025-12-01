package.path = "tests/?.lua;" .. package.path
local lu = require "luaunit"
local use_ref = os.getenv("REF") == "1"
--- @module 'ariadne'
local ariadne = require(use_ref and "ariadne" or "musubi")

-- print a demo
if #arg == 0 then
  local cg = ariadne.colorgen()
  local report =
      ariadne.report(12)
      :code "3"
      :title("Error", "Incompatible types")
      :label(33, 33):message("This is of type Nat"):color(cg:next())
      :label(43, 45):message("This is of type Str"):color(cg:next())
      :label(12, 48):message("This values are outputs of this match expression"):color(cg:next())
      :label(1, 48):message("The definition has a problem"):color(cg:next())
      :label(51, 76):message("Usage of definition here"):color(cg:next())
      :note("Outputs of match expressions must coerce to the same type")
      :source([[
def five = match () in {
	() => 5,
	() => "5",
}

def six =
    five
    + 1
]], "sample.tao"):render()
  print("report count=", #report)
  print(report)
end

---@param text string
---@return string
local function remove_trailing(text)
  return (text:gsub("%s+\n", "\n"):gsub("%s+\n$", "\n"))
end

---@return ConfigAPI
local function no_color_ascii()
  return ariadne.config()
      :color(false)
      :char_set "ascii"
end

local TestColor = {}
do
  function TestColor.test_colors()
    local gen = ariadne.colorgen()
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
  function TestWrite.test_empty()
    local msg = remove_trailing(
      ariadne.report(0)
      :config(no_color_ascii())
      :source(""):render()
    )

    lu.assertEquals(msg, [=[
Error:
]=])

    msg = remove_trailing(
      ariadne.report(0)
      :config(no_color_ascii())
      :label(1, 1):message("Empty source")
      :source(""):render()
    )

    lu.assertEquals(msg, [=[
Error:
   ,-[ <unknown>:?:? ]
   |
 1 |
   | |
   | `- Empty source
---'
]=])
  end

  function TestWrite.test_one_message()
    local msg = remove_trailing(
      ariadne.report(0)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :source("")
      :render()
    )

    lu.assertEquals(msg, ([=[
Error: can't compare apples with oranges
]=]))
  end

  function TestWrite.test_two_labels_without_messages()
    local text = "apple == orange;"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 5)
      :label(10, 15)
      :source(text):render()
    )

    lu.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 | apple == orange;
   | ^^^^^    ^^^^^^
---'
]=]))
  end

  function TestWrite.test_label_attach_start_with_blank_line()
    local text = "alpha\nbravo\ncharlie\n"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():label_attach "start")
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(10, 15):message("This is an orange")
      :source(text):render()
    )

    lu.assertEquals(msg, ([=[
Error: can't compare apples with oranges
   ,-[ <unknown>:1:1 ]
   |
 1 |     alpha
   |     |^^^^
   |     `------ This is an apple
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
      ariadne.report(1)
      :config(no_color_ascii():compact(true))
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(10, 15):message("This is an orange")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare äpplës with örängës")
      :label(1, 5):message("This is an äpplë")
      :label(10, 15):message("This is an örängë")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii():index_type "byte")
      :title("Error", "can't compare äpplës with örängës")
      :label(1, 7):message("This is an äpplë")
      :label(12, 20):message("This is an örängë")
      :source(text):render()
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
      ariadne.report(12)
      :config(no_color_ascii():index_type "byte")
      :title("Error", "can't compare äpplës with örängës")
      :label(1, 7):message("This is an äpplë")
      :label(12, 20):message("This is an örängë")
      :source(text):render()
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

  function TestWrite.test_tab_width()
    local code = "a\tbcd\te"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():tab_width(5))
      :title("Error", "tab width test")
      :label(1, 3):message("This spans a tab")
      :label(7, 7):message("This skips two tab")
      :source(code):render()
    )
    lu.assertEquals(msg, [=[
Error: tab width test
   ,-[ <unknown>:1:1 ]
   |
 1 | a    bcd  e
   | ^|^^^^    |
   |  `----------- This spans a tab
   |           |
   |           `-- This skips two tab
---'
]=])
  end

  function TestWrite.test_label_at_end_of_long_line()
    local text = string.rep("apple == ", 100) .. "orange"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():index_type "byte")
      :title("Error", "can't compare apples with oranges")
      :label(#text - 5, #text):message("This is an orange")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii():index_type "byte")
      :title("Error", "unexpected end of file")
      :label(9):message("Unexpected end of file")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "unexpected end of file")
      :label(1, 0):message("No more fruit!")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "unexpected end of file")
      :label(1, 0):message("No more fruit!")
      :help("have you tried going to the farmer's market?")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "unexpected end of file")
      :label(1, 0):message("No more fruit!")
      :note("eat your greens!")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "unexpected end of file")
      :label(1, 0):message("No more fruit!")
      :note("eat your greens!")
      :help("have you tried going to the farmer's market?")
      :source(text):render()
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
          return ariadne.report(1)
              :config(no_color_ascii():index_type "byte")
              :title("Error", "Label")
              :label(i, j):message("Label")
              :source(text):render()
        end)
        lu.assertTrue(ok, result)
        lu.assertEquals(type(result), "string")
      end
    end
  end

  function TestWrite.test_multiline_label()
    local text = "apple\n==\norange"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :label(1, #text):message("illegal comparison")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :label(1, #text):message("URL")
      :label(1, colon_start):message("scheme")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(1, 5):message("Have I mentioned that this is an apple?")
      :label(1, 5):message("No really, have I mentioned that?")
      :label(10, 15):message("This is an orange")
      :label(10, 15):message("Have I mentioned that this is an orange?")
      :label(10, 15):message("No really, have I mentioned that?")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(10, 15):message("This is an orange")
      :note("stop trying ... this is a fruitless endeavor")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii():compact(true))
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(10, 15):message("This is an orange")
      :note("stop trying ... this is a fruitless endeavor")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(10, 15):message("This is an orange")
      :help("have you tried peeling the orange?")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 5):message("This is an apple")
      :label(10, 15):message("This is an orange")
      :help("have you tried peeling the orange?")
      :note("stop trying ... this is a fruitless endeavor")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 15):message("This is a strange comparison")
      :note("No need to try, they can't be compared.")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 15):message("This is a strange comparison")
      :note("No need to try, they can't be compared.")
      :note("Yeah, really, please stop.")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "can't compare apples with oranges")
      :label(1, 15):message("This is a strange comparison")
      :note("No need to try, they can't be compared.")
      :note("Yeah, really, please stop.\nIt has no resemblance.")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Advice", "can't compare apples with oranges")
      :label(1, 15):message("This is a strange comparison")
      :help("No need to try, they can't be compared.")
      :help("Yeah, really, please stop.\nIt has no resemblance.")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "line offset demo")
      :label(12, 22):message("Second line")
      :source(text, nil, 9):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "ordered labels")
      :label(1, 3):message("Left")
      :label(4, 6):order(-10):message("Right")
      :source(text):render()
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
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():label_attach "start")
      :title("Error", "gaps between labels")
      :label(1, 5):message("first")
      :label(13, 19):message("third")
      :source(text):render()
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
    local msg = remove_trailing(
      ariadne.report(3)
      :config(no_color_ascii():label_attach "end")
      :title("Error", "zero length span")
      :label(3):message("point")
      :source(text):render()
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
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "overlap priorities")
      :label(1, 4):message("weak")
      :label(2, 5):message("strong"):priority(10):color(
        function(k)
          if k == "reset" then return "]" end
          return "["
        end)
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "stacked arrows")
      :label(1, 3):message("left")
      :label(5, 8):message("right")
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :code("E100")
      :title("Notice", "custom kind")
      :source("x"):render()
    )

    lu.assertEquals(msg, ([=[
[E100] Notice: custom kind
]=]))
  end

  function TestWrite.test_warning_and_advice()
    local warning = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Warning", "careful")
      :source("w"):render()
    )
    local advice = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Advice", "consider")
      :source("a"):render()
    )

    lu.assertEquals(warning, ([=[
Warning: careful
]=]))
    lu.assertEquals(advice, ([=[
Advice: consider
]=]))
  end

  function TestWrite.test_byte_index_out_of_bounds()
    local msg = remove_trailing(
      ariadne.report(100)
      :config(no_color_ascii():index_type "byte")
      :title("Error", "unknown position")
      :source("hi"):render()
    )

    lu.assertEquals(msg, ([=[
Error: unknown position
]=]))
  end

  function TestWrite.test_invalid_label()
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "invalid label")
      :label(999, 1000):message("ignored")
      :source("short"):render()
    )

    lu.assertEquals(msg, ([=[
Error: invalid label
   ,-[ <unknown>:1:1 ]
   |
 1 | short
   |      |
   |      `- ignored
---'
]=]))
  end

  -- Additional coverage-focused tests (expected outputs intentionally left blank)
  function TestWrite.test_oob_location_with_label_byte()
    local text = "hi"
    local msg = remove_trailing(
      ariadne.report(100)
      :config(no_color_ascii():index_type "byte")
      :title("Error", "oob location with label")
      :label(1, 1):message("label")
      :source(text):render()
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

  function TestWrite.test_multiline_without_msg()
    local text = "line1\nline2"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "multiline label without message")
      :label(1, #text)
      :source(text):render()
    )

    lu.assertEquals(msg, ([=[
Error: multiline label without message
   ,-[ <unknown>:1:1 ]
   |
 1 | ,-> line1
 2 | `-> line2
---'
]=]))
  end

  function TestWrite.test_two_multiline_without_msg()
    local text = "first second\nline2"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "two multiline label without message")
      :label(1, #text)
      :label(7, #text)
      :source(text):render()
    )

    lu.assertEquals(msg, ([=[
Error: two multiline label without message
   ,-[ <unknown>:1:1 ]
   |
 1 | ,---> first second
   | |           ^
   | | ,---------'
 2 | | `-> line2
   | |         ^
   | `---------'
---'
]=]))
  end

  function TestWrite.test_mix_multiline_without_msg()
    local text = "first second\nline2"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "mix multiline label without message")
      :label(1, #text)
      :label(14, #text):message("inline")
      :label(7, #text)
      :source(text):render()
    )

    lu.assertEquals(msg, ([=[
Error: mix multiline label without message
   ,-[ <unknown>:1:1 ]
   |
 1 | ,---> first second
   | |           ^
   | | ,---------'
 2 | | `-> line2
   | |     ^^|^|
   | |       `---- inline
   | |         |
   | `---------'
---'
]=]))
  end

  function TestWrite.test_multiline_sort_and_padding()
    -- First line has trailing spaces to exercise split_at_column padding; two
    -- multiline labels with messages ensure sorting comparators run.
    local text = "abc   \nmid\nxyz"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "multiline sort & padding")
      :label(5, 13):message("outer") -- from trailing spaces into last line
      :label(9, 13):message("inner") -- spans mid->x
      :source(text):render()
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
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "pointer and connectors")
      :label(2, 8):message("multi") -- multi spanning line1->line2
      :label(9, 10):message("inline")
      :source(text):render()
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
      ariadne.report(12)
      :config(no_color_ascii())
      :code "3"
      :title("Error", "Incompatible types")
      :label(33, 33):message("This is of type Nat")
      :label(43, 45):message("This is of type Str")
      :label(12, 48):message("This values are outputs of this match expression")
      :label(1, 48):message("The definition has a problem")
      :label(51, 76):message("Usage of definition here")
      :note("Outputs of match expressions must coerce to the same type")
      :source(text, "sample.tao"):render()
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
    local msg = remove_trailing(
      ariadne.report(1, 1)
      :config(no_color_ascii())
      :title("Error", "cross-file error")
      :source("apple", "file1.lua")
      :label(1, 5, 1)
      :source("orange", "file2.lua")
      :label(1, 6, 2)
      :render()
    )
    lu.assertEquals(msg, [[
Error: cross-file error
   ,-[ file1.lua:1:1 ]
   |
 1 | apple
   | ^^^^^
   |
   |-[ file2.lua:1:1 ]
   |
 1 | orange
   | ^^^^^^
---'
]])
  end

  -- Test 2: Compact mode with multiline arrows (line 1413)
  function TestWrite.test_compact_multiline_arrows()
    local src = "apple\norange\nbanana"
    local msg = ariadne.report(1)
        :config(no_color_ascii():compact(true):multiline_arrows(true))
        :title("Error", "multiline span")
        :label(1, 12):message("crosses lines")
        :source(src):render()
    lu.assertEquals(msg, [=[
Error: multiline span
   ,-[ <unknown>:1:1 ]
 1 |,>apple
 2 ||>orange
   |`--------- crosses lines
]=])
  end

  function TestWrite.test_label_end_is_newline()
    local src = "apple\n\n\norange"
    local msg = remove_trailing(ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test default colors")
      :label(1, 6):message("spans multiple lines")
      :source(src):render())
    lu.assertEquals(msg, [[
Error: test default colors
   ,-[ <unknown>:1:1 ]
   |
 1 | apple
   | ^^^|^^
   |    `---- spans multiple lines
---'
]])
  end

  function TestWrite.test_default_color_categories()
    local cfg = ariadne.config { char_set = "ascii" }
    local src = "apple\n\n\norange"
    local msg = ariadne.report(1)
        :config(cfg)
        :title("Error", "test default colors")
        :label(1, 6):message("spans multiple lines")
        :note("note with default colors")
        :source(src):render()
    -- Expected: "Error:" in red, skipped margin ":" in dim gray
    msg = ("%q"):format(msg)
    lu.assertEquals(msg, [[
"\27[31mError:\27[0m test default colors\
   \27[38;5;246m,-[\27[0m <unknown>:1:1 \27[38;5;246m]\27[0m\
   \27[38;5;246m|\27[0m\
 \27[38;5;246m1 |\27[0m \27[39mapple\27[0m\
   \27[38;5;240m|\27[0m \27[39m^^^|^^\27[0m  \
   \27[38;5;240m|\27[0m    \27[39m`----\27[0m spans multiple lines\
   \27[38;5;240m|\27[0m \
   \27[38;5;240m|\27[0m \27[38;5;115mNote: note with default colors\27[0m\
\27[38;5;246m---'\27[0m\
"]])

    msg = ("%q"):format(remove_trailing(
      ariadne.report(1)
      :config(cfg)
      :title("Advice", "test default colors")
      :source(src):render()
    ))
    lu.assertEquals(msg, [[
"\27[38;5;147mAdvice:\27[0m test default colors\
"]])

    msg = ("%q"):format(remove_trailing(
      ariadne.report(1)
      :config(cfg)
      :title("Warning", "test default colors")
      :source(src):render()
    ))
    lu.assertEquals(msg, [[
"\27[33mWarning:\27[0m test default colors\
"]])
  end -- Test 2: Compact mode with multiline arrows (line 1413)

  -- Test 3: cross_gap disabled (line 1409)
  function TestWrite.test_cross_gap_disabled()
    local src = "apple\norange\nbanana\ngrape"
    local msg = remove_trailing(ariadne.report(1)
      :config(no_color_ascii():cross_gap(false))
      :title("Error", "test cross_gap")
      :label(1, 19):message("span 1")
      :label(21, 25):message("span 2")
      :source(src):render()
    )
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
    local src = "apple orange"
    local msg = remove_trailing(ariadne.report(1)
      :config(no_color_ascii():underlines(false))
      :title("Error", "no underlines")
      :label(1, 5):message("label")
      :source(src):render()
    )
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
    local src = "apple orange banana"
    local msg = remove_trailing(ariadne.report(1)
      :config(no_color_ascii():underlines(true))
      :title("Error", "overlapping same priority")
      :label(3, 7):message("short"):priority(1)
      :label(4, 7):message("shortest"):priority(1)
      :label(1, 10):message("long"):priority(1)
      :source(src):render()
    )
    -- The shorter label should win when priority is the same
    lu.assertEquals(msg, [[
Error: overlapping same priority
   ,-[ <unknown>:1:1 ]
   |
 1 | apple orange banana
   | ^^^^||^^^^
   |     `------- short
   |      |
   |      `------ shortest
   |      |
   |      `------ long
---'
]])
  end

  -- Test 8: compact multiline with uarrow (line 1349)
  function TestWrite.test_compact_multiline_uarrow()
    local cfg = no_color_ascii()
    local src = "apple\norange\nbanana"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():compact(true):multiline_arrows(true))
      :title("Error", "compact uarrow")
      :label(1, 12):message("multiline")
      :source(src):render()
    )
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
    -- Based on test_pointer_and_connectors but with cross_gap disabled
    local text = "abcde\nfghij\n"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():cross_gap(false))
      :title("Error", "xbar test")
      :label(2, 8):message("multi")
      :label(9, 10):message("inline")
      :source(text):render()
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
    -- Two multiline labels: one starts earlier, one starts later on line 1
    -- This should trigger the uarrow condition at line 1343
    local src = "abcdefgh\nijklmnop\nqrstuvwx"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():compact(true))
      :title("Error", "two multiline labels")
      :label(1, 18):message("outer")
      :label(3, 19):message("inner")
      :source(src):render()
    )
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
    msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():compact(true):char_set "unicode")
      :title("Error", "two multiline labels")
      :label(1, 18):message("outer")
      :label(3, 19):message("inner")
      :source(src):render()
    )
    lu.assertEquals(msg, [[
Error: two multiline labels
   ╭─[ <unknown>:1:1 ]
 1 │╭─▶abcdefgh
   ││╭───╯
 2 │├─▶ijklmnop
   │╰──────────── outer
 3 │ ├▶qrstuvwx
   │ ╰────────── inner
]])
  end

  -- Test 11: compact mode with two multiline labels ending at same col (line 1340)
  function TestWrite.test_compact_multiline_same_end_col()
    -- Two multiline labels both ending at the same column
    -- This triggers the uarrow at line 1340
    -- labelA: char 1-6 (line 1 col 1 to line 2 col 1)
    -- labelB: char 2-6 (line 1 col 2 to line 2 col 1)
    local src = "abcd\nefgh\nijkl\n"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():compact(true))
      :title("Error", "test two multiline labels ending at same col")
      :label(1, 6):message("labelA spans 1-6")
      :label(2, 6):message("labelB spans 2-6")
      :source(src):render()
    )
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
    local src = "apple\norange\nbanana"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():compact(true))
      :title("Error", "uarrow test")
      :label(1, 7):message("inner"):order(1)
      :label(2, 14):message("outer"):order(2)
      :label(1, 8):message("outer outer"):order(0)
      :source(src):render()
    )
    lu.assertEquals(msg, [=[
Error: uarrow test
   ,-[ <unknown>:1:1 ]
 1 | ,->apple
   | |,-'^
   |,----'
 2 |||->orange
   ||`---------- outer outer
   || `-^------- inner
 3 ||-->banana
   |`---------- outer
]=])
  end

  function TestWrite.test_margin_xbar()
    local src = "apple\norange\nbanana\nstrawberry"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():cross_gap(false))
      :title("Error", "margin xbar test")
      :label(1, 14):message("outer"):order(0)
      :label(7, 21):message("inner"):order(1)
      :source(src):render()
    )
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

  function TestWrite.test_emoji()
    local src = "apple 🍎 orange 🍊 banana 🍌"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "emoji test")
      :label(7, 7):message("first emoji")
      :label(16, 16):message("second emoji")
      :label(25, 25):message("third emoji")
      :source(src):render()
    )
    lu.assertEquals(msg, [[
Error: emoji test
   ,-[ <unknown>:1:1 ]
   |
 1 | apple 🍎 orange 🍊 banana 🍌
   |       |^        |^        |^
   |       `----------------------- first emoji
   |                 |         |
   |                 `------------- second emoji
   |                           |
   |                           `--- third emoji
---'
]])
  end

  function TestWrite.test_unimportant_color()
    local text = "this is a color test"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(ariadne.config())
      :title("Error", "unimportant color test")
      :label(11, 15):message("color is here")
      :source(text):render()
    )
    msg = ("%q"):format(msg)
    lu.assertNotNil(msg:find("\\27%[38;5;249m"))
  end
end

local TestLocLimit = {}
do
  -- Phase 1: Header Truncation Tests (MVP: simple suffix truncation)
  -- Header format: "   ,-[ {path}:{line}:{col} ]"
  -- Fixed width = 7 (before) + 2 (after) = 9 chars
  -- Available for path:line:col = line_width - 9
  -- Ellipsis width = 3 (ASCII "...")
  -- Suffix width = available - 3

  function TestLocLimit.test_header_no_truncation_short_path()
    -- Path is short, no truncation needed
    local src = "apple"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(60))
      :title("Error", "test_header_no_truncation_short_path")
      :label(1, 1):message("label")
      :source(src, "file.lua"):render()
    )
    lu.assertEquals(msg, [[
Error: test_header_no_truncation_short_path
   ,-[ file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_truncation_long_path()
    -- Path exceeds line_width, should truncate from start (keep suffix)
    -- Generate long path: ("dir/"):rep(20) = "dir/dir/.../dir/" (80 chars)
    local src = "apple"
    local long_path = ("dir/"):rep(20) .. "file.lua"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(40))
      :title("Error", "test_header_truncation_long_path")
      :label(1, 1):message("label")
      :source(src, long_path):render()
    )
    lu.assertEquals(msg, [[
Error: test_header_truncation_long_path
   ,-[ ...dir/dir/dir/dir/file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_truncation_large_line_number()
    -- Generate a file with many lines to test large line numbers
    -- Use ("line\n"):rep(200) instead of manual loop
    local src = ("line\n"):rep(200) .. "target"
    local long_path = ("dir/"):rep(20) .. "file.lua"

    -- Line 201 is the "target" line, char position = 200*5 + 1 = 1001
    local msg = remove_trailing(
      ariadne.report(1001)
      :config(no_color_ascii():limit_width(45))
      :title("Error", "test_header_truncation_large_line_number")
      :label(1001, 1001):message("label")
      :source(src, long_path):render()
    )
    -- Available = 45 - 9 - 3 = 33, loc = 5, ellipsis = 3, suffix = 25
    -- Expected: ".../dir/dir/dir/dir/file.lua" (25 chars fits)
    lu.assertEquals(msg, [[
Error: test_header_truncation_large_line_number
     ,-[ .../dir/dir/dir/dir/file.lua:201:1 ]
     |
 201 | target
     | |
     | `-- label
-----'
]])
  end

  function TestLocLimit.test_header_truncation_utf8_path()
    -- Path with UTF-8 characters (CJK chars are width 2)
    -- "目录" = 4 display width, repeat 20 times = 80 display width
    local text = "apple"
    local utf8_path = ("目录/"):rep(20) .. "文件.lua"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(40))
      :title("Error", "test_header_truncation_utf8_path")
      :label(1, 1):message("label")
      :source(text, utf8_path):render()
    )
    lu.assertEquals(msg, [[
Error: test_header_truncation_utf8_path
   ,-[ .../目录/目录/目录/文件.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_truncation_tab_in_path()
    -- Path contains tab character (should normalize to spaces before width calc)
    -- Tab width = 4 (default)
    local text = "apple"
    local tab_path = ("dir\t"):rep(20) .. "file.lua"
    -- Tab normalized to single space: "dir " * 20 + "file.lua" = 80 + 8 = 88 chars
    -- line_width=40, line_no_width=1, loc="1:1"(3 chars)
    -- fixed_width = 1 + 9 + 3 = 13
    -- avail = 40 - 13 - 3(ellipsis) = 24
    -- Expected: "..." + 24 chars suffix = "...dir dir dir dir file.lua"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(40))
      :title("Error", "test_header_truncation_tab_in_path")
      :label(1, 1):message("label")
      :source(text, tab_path):render()
    )
    -- Expected: tabs normalized to spaces, then suffix truncated
    -- "...dir    file.lua:1:1" (approx 22 chars)
    lu.assertEquals(msg, [[
Error: test_header_truncation_tab_in_path
   ,-[ ...dir dir dir dir file.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_truncation_very_narrow()
    -- Very narrow line_width: available = 25 - 9 = 16
    local text = "apple"
    local long_path = ("dir/"):rep(20) .. "source.lua"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(25))
      :title("Error", "test_header_truncation_very_narrow")
      :label(1, 1):message("label")
      :source(text, long_path):render()
    )
    -- Available = 25 - 9 - 1 = 15, loc = 3, ellipsis = 3, suffix = 9
    -- "/source.lua" = 9 chars, fits
    lu.assertEquals(msg, [[
Error: test_header_truncation_very_narrow
   ,-[ ...r/source.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_no_truncation_when_nil()
    -- line_width = nil, no truncation should occur
    local text = "apple"
    local long_path = ("dir/"):rep(20) .. "file.lua"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(nil))
      :title("Error", "test_header_no_truncation_when_nil")
      :label(1, 1):message("label")
      :source(text, long_path):render()
    )
    -- Full path should be displayed (80 chars total)
    local expected_header = ",-[ " .. long_path .. ":1:1 ]"
    lu.assertEquals(msg, [[
Error: test_header_no_truncation_when_nil
   ]] .. expected_header .. [[

   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_truncation_exact_boundary()
    -- Path exactly matches available width, no truncation
    local text = "apple"
    -- line_width=30, line_no_width=1, loc="1:1"(3 chars)
    -- fixed_width = 1 + 9 + 3 = 13
    -- id="short/path.lua" = 14 chars, total = 13 + 14 + 3 = 30, exactly fits
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(30))
      :title("Error", "test_header_truncation_exact_boundary")
      :label(1, 1):message("label")
      :source(text, "short/path.lua"):render()
    )
    -- "short/path.lua:1:1" = 18 chars, under 21, no truncation
    lu.assertEquals(msg, [[
Error: test_header_truncation_exact_boundary
   ,-[ short/path.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end

  function TestLocLimit.test_header_truncation_one_over_boundary()
    -- Path exceeds available width by exactly 1 char
    local text = "apple"
    local long_name = ("x"):rep(15) .. ".lua"
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(30))
      :title("Error", "test_header_truncation_one_over_boundary")
      :label(1, 1):message("label")
      :source(text, long_name):render()
    )
    lu.assertEquals(msg, [[
Error: test_header_truncation_one_over_boundary
   ,-[ ...xxxxxxxxxx.lua:1:1 ]
   |
 1 | apple
   | |
   | `-- label
---'
]])
  end
end

TestLineLimit = {}
do
  function TestLineLimit.test_single_label_at_end_of_long_line()
    -- Label at the very end of a 900+ char line
    -- Should show ellipsis prefix + local context
    local text = string.rep("apple == ", 100) .. "orange"
    -- Total length: 100*9 + 6 = 906 chars
    -- Label is at chars 901-906 ("orange")
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_single_label_at_end_of_long_line")
      :label(901, 906):message("This is an orange")
      :source(text):render()
    )

    lu.assertEquals(msg, [[
Error: test_single_label_at_end_of_long_line
   ,-[ <unknown>:1:1 ]
   |
 1 | ... apple == apple == apple == apple == apple == orange
   |                                                  ^^^|^^
   |                                                     `---- This is an orange
---'
]])
  end

  function TestLineLimit.test_tab_width()
    local code = ("\t"):rep(20) .. "error"
    local msg = remove_trailing(
      ariadne.report(21)
      :config(no_color_ascii():limit_width(40):tab_width(4))
      :title("Error", "test_tab_width")
      :label(21, 25):message("here")
      :source(code):render()
    )
    lu.assertEquals(msg, [[
Error: test_tab_width
   ,-[ <unknown>:1:21 ]
   |
 1 | ...                    error
   |                        ^^|^^
   |                          `---- here
---'
]])
  end

  function TestLineLimit.test_single_label_in_middle_of_long_line()
    -- Label in the middle of a long line
    -- Should center the label in the available width
    local prefix = string.rep("a", 400)
    local target = "error"
    local suffix = string.rep("b", 400)
    local text = prefix .. target .. suffix
    -- Total: 805 chars, label at 401-405
    local msg = remove_trailing(
      ariadne.report(401)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_single_label_in_middle_of_long_line")
      :label(401, 405):message("found here")
      :source(text):render()
    )

    lu.assertEquals(msg, [[
Error: test_single_label_in_middle_of_long_line
   ,-[ <unknown>:1:401 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |                              ^^|^^
   |                                `---- found here
---'
]])
  end

  function TestLineLimit.test_small_msg()
    local text = ("a"):rep(400) .. "error" .. ("b"):rep(400)
    local msg = remove_trailing(
      ariadne.report(401)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_small_msg")
      :label(401, 405):message("1")
      :source(text):render()
    )

    lu.assertEquals(msg, [[
Error: test_small_msg
   ,-[ <unknown>:1:401 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |                                  ^^|^^
   |                                    `---- 1
---'
]])
  end

  function TestLineLimit.test_minimum_line_width()
    -- Label at the start of a long line
    -- Should NOT show ellipsis, just truncate the end
    local text = ("a"):rep(400) .. "error" .. ("b"):rep(400)
    local label = "a very long message that exceeds the line width significantly"
    local msg = remove_trailing(
      ariadne.report(401)
      :config(no_color_ascii():limit_width(20))
      :title("Error", "test_minimum_line_width")
      :label(401, 405):message(label)
      :source(text):render()
    )

    -- Label is at the start, so skip_chars = 0
    -- Just show first 75 chars (no ellipsis needed)
    lu.assertEquals(msg, [[
Error: test_minimum_line_width
   ,-[ <unknown>:1:401 ]
   |
 1 | ...errorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |    ^^|^^
   |      `---- a very long message that exceeds the line width significantly
---'
]])
  end

  function TestLineLimit.test_fit_line_width()
    -- Label at the start of a long line
    -- Should NOT show ellipsis, just truncate the end
    local text = ("a"):rep(55) .. "error" .. ("b"):rep(16)
    local msg = remove_trailing(
      ariadne.report(401)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_fit_line_width")
      :label(56, 60):message("at start")
      :source(text):render()
    )

    -- Label is at the start, so skip_chars = 0
    -- Just show first 75 chars (no ellipsis needed)
    lu.assertEquals(msg, [[
Error: test_fit_line_width
   ,-[ <unknown>:?:? ]
   |
 1 | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbb...
   |                                                        ^^|^^
   |                                                          `---- at start
---'
]])
  end

  function TestLineLimit.test_single_label_at_start_of_long_line()
    -- Label at the start of a long line
    -- Should NOT show ellipsis, just truncate the end
    local text = "error" .. string.rep("x", 900)
    -- Label at 1-5
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_single_label_at_start_of_long_line")
      :label(1, 5):message("at start")
      :source(text):render()
    )

    -- Label is at the start, so skip_chars = 0
    -- Just show first 75 chars (no ellipsis needed)
    lu.assertEquals(msg, [[
Error: test_single_label_at_start_of_long_line
   ,-[ <unknown>:1:1 ]
   |
 1 | errorxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx...
   | ^^|^^
   |   `---- at start
---'
]])
  end

  function TestLineLimit.test_no_windowing_when_line_fits()
    -- Line is short enough to fit within line_width
    -- Should NOT apply windowing
    local text = "short line with error"
    local msg = remove_trailing(
      ariadne.report(17)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_no_windowing_when_line_fits")
      :label(17, 21):message("here")
      :source(text):render()
    )

    -- Line is only 21 chars, fits easily in 75 available
    -- No windowing needed
    lu.assertEquals(msg, [[
Error: test_no_windowing_when_line_fits
   ,-[ <unknown>:1:17 ]
   |
 1 | short line with error
   |                 ^^|^^
   |                   `---- here
---'
]])
  end

  function TestLineLimit.test_no_windowing_when_line_width_nil()
    -- line_width = nil, should display full line
    local text = string.rep("a", 200)
    local msg = remove_trailing(
      ariadne.report(195)
      :config(no_color_ascii():limit_width(nil))
      :title("Error", "test_no_windowing_when_line_width_nil")
      :label(195, 200):message("end")
      :source(text):render()
    )

    -- Full line should be displayed (200 chars)
    local expected_line = " 1 | " .. text
    lu.assertTrue(msg:find(expected_line, 1, true) ~= nil, "Should show full line")
  end

  function TestLineLimit.test_multiple_labels_on_long_line()
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
    local msg = remove_trailing(
      ariadne.report(101)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_multiple_labels_on_long_line")
      :label(101, 105):message("first error")
      :label(306, 309):message("second warning")
      :source(text):render()
    )

    lu.assertEquals(msg, [[
Error: test_multiple_labels_on_long_line
   ,-[ <unknown>:1:101 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaerrorbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb...
   |                             ^^|^^
   |                               `---- first error
 1 | ...bbbbbbbbbbbbbbbbbbbbbbbbwarnccccccccccccccccccccccccccccccccccccccccc...
   |                            ^^|^
   |                              `--- second warning
---'
]])
  end

  function TestLineLimit.test_cjk_characters_in_line()
    -- Line with CJK characters (width 2 each)
    -- Should correctly calculate display width
    local text = string.rep("中", 50) .. "错误" .. string.rep("文", 50)
    -- Total: 102 CJK chars = 204 display width
    -- Label "错误" at position 51-52 (2 chars, 4 display width)
    local msg = remove_trailing(
      ariadne.report(51)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_cjk_characters_in_line")
      :label(51, 52):message("这是错误")
      :source(text):render()
    )

    lu.assertEquals(msg, [[
Error: test_cjk_characters_in_line
   ,-[ <unknown>:1:51 ]
   |
 1 | ...中中中中中中中中中中中中中错误文文文文文文文文文文文文文文文文文文文...
   |                              ^^|^
   |                                `----- 这是错误
---'
]])
  end

  function TestLineLimit.test_mixed_ascii_cjk_characters()
    -- Mixed ASCII and CJK characters
    -- ASCII width 1, CJK width 2
    local prefix = string.rep("a", 200)
    local text = prefix .. "hello世界error错误test"
    -- Label on "error错误" (5 ASCII + 2 CJK = 7 chars)
    -- Position: 201-207 (char positions)
    local msg = remove_trailing(
      ariadne.report(201)
      :config(no_color_ascii():limit_width(80))
      :title("Error", "test_mixed_ascii_cjk_characters")
      :label(206, 212):message("mixed error")
      :source(text):render()
    )

    lu.assertEquals(msg, [[
Error: test_mixed_ascii_cjk_characters
   ,-[ <unknown>:1:201 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaahello世界error错误test
   |                                                   ^^^^^|^^^
   |                                                        `------- mixed error
---'
]])
  end

  function TestLineLimit.test_order_disrupts_spatial_clustering()
    local text = ("a"):rep(100)
    local msg = remove_trailing(
      ariadne.report(10)
      :config(no_color_ascii():limit_width(60))
      :title("Error", "test_order_disrupts_spatial_clustering")
      :label(10):message("label2"):order(1)
      :label(50):message("label1"):order(0)
      :source(text):render()
    )
    lu.assertEquals(msg, [[
Error: test_order_disrupts_spatial_clustering
   ,-[ <unknown>:1:10 ]
   |
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
   |    |                                       |
   |    |                                       `- label1
   |    |
   |    `----------------------------------------- label2
---'
]])
  end

  function TestLineLimit.test_cluster_width_calculation()
    local text = ("a"):rep(200)
    local msg = remove_trailing(
      ariadne.report(100)
      :config(no_color_ascii():limit_width(60))
      :title("Error", "test_cluster_width_calculation")
      :label(10, 10):message("labelA")
      :label(10, 60):message("labelB")
      :source(text):render()
    )
    lu.assertEquals(msg, [[
Error: test_cluster_width_calculation
   ,-[ <unknown>:1:100 ]
   |
 1 | aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
   |          |
   |          `-- labelA
 1 | ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
   |    ^^^^^^^^^^^^^^^^^^^^^^^^^|^^^^^^^^^^^^^^^^^^^^^^^^^
   |                             `--------------------------- labelB
---'
]])
  end

  function TestLineLimit.test_margin_per_cluster()
    local src = ("a"):rep(200) .. "\nbbbbb"
    local msg = remove_trailing(
      ariadne.report(100)
      :config(no_color_ascii():limit_width(50))
      :title("Error", "test_margin_per_cluster")
      :label(10, 204):message("labelA")
      :label(150, 205):message("labelB")
      :label(160, 206):message("labelC")
      :source(src):render()
    )
    lu.assertEquals(msg, [[
Error: test_margin_per_cluster
   ,-[ <unknown>:1:100 ]
   |
 1 | ,-----> aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
 1 | | ,---> ...aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa...
   | | |                        ^
   | | | ,----------------------'
 2 | |-----> bbbbb
   | | | |      ^^
   | `-------------- labelA
   |   | |      ||
   |   `--------^--- labelB
   |     |       |
   |     `-------^-- labelC
---'
]])
  end

  function TestLineLimit.test_multiline()
    local src = ("first line\n") .. ("a"):rep(200)
    local msg = remove_trailing(
      ariadne.report(15)
      :config(no_color_ascii():limit_width(50))
      :title("Error", "test_multiline")
      :label(7, #src):message("multiline label")
      :source(src):render()
    )
    lu.assertEquals(msg, [[
Error: test_multiline
   ,-[ <unknown>:2:4 ]
   |
 1 | ,-> first line
 2 | |-> ...aaaaaaaaaaaaaaaaaaaa
   | |
   | `---------------------------- multiline label
---'
]])
  end
end

local TestFile = {}
do
  function TestFile.test_file_error()
    local tmpname = os.tmpname()
    -- this is a write only file
    local file = assert(io.open(tmpname, "w"))
    file:write("line one\nline two with error\nline three\n")

    local msg =
        ariadne.report(12)
        :config(no_color_ascii())
        :title("Error", "test_file_error")
        :label(12, 16):message("found here")
        :source(file)

    lu.assertErrorMsgContains("musubi: file operation failed",
      function() msg:render() end)

    file:close()
    os.remove(tmpname)
  end

  local function write_temp_file(content)
    local tmpname = os.tmpname()
    local file = assert(io.open(tmpname, "w"))
    file:write(content)
    file:close()
    return tmpname
  end

  function TestFile.test_file_empty()
    -- create an empty file
    local tmpname = write_temp_file("")

    local file = assert(io.open(tmpname, "r"))
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test_file_empty")
      :label(1, 1):message("label")
      :source(file):render()
    )
    file:close()

    lu.assertEquals(msg, [[
Error: test_file_empty
   ,-[ <unknown>:1:1 ]
   |
 1 |
   | |
   | `- label
---'
]])
  end

  function TestFile.test_file_multiline()
    local code = "first line\nsecond line with error\nthird line\n"
    local tmpname = write_temp_file(code)

    local file = assert(io.open(tmpname, "r"))
    local msg = remove_trailing(
      ariadne.report(14)
      :config(no_color_ascii())
      :title("Error", "test_file_multiline")
      :label(29, 33):message("found here")
      :label(1, #code):message("whole file")
      :source(file):render()
    )
    file:close()
    os.remove(tmpname)

    lu.assertEquals(msg, [[
Error: test_file_multiline
   ,-[ <unknown>:2:3 ]
   |
 1 | ,-> first line
 2 | |   second line with error
   | |                    ^^|^^
   | |                      `---- found here
 3 | |-> third line
   | |
   | `---------------- whole file
---'
]])
  end

  function TestFile.test_file_end()
    local code = "こにちわ"
    local tmpname = write_temp_file(code)

    local file = assert(io.open(tmpname, "r"))
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test_file_end")
      :label(1, #code):message("label")
      :source(file):render()
    )
    lu.assertEquals(msg, [[
Error: test_file_end
   ,-[ <unknown>:1:1 ]
   |
 1 | こにちわ
   | ^^^^|^^^
   |     `----- label
---'
]])
    file:close()
    os.remove(tmpname)

    code = "emoji test 🍎🍊🍌"
    tmpname = write_temp_file(code)
    file = assert(io.open(tmpname, "r"))
    msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test_file_emoji")
      :label(1, #code):message("label")
      :source(file):render()
    )
    lu.assertEquals(msg, [[
Error: test_file_emoji
   ,-[ <unknown>:1:1 ]
   |
 1 | emoji test 🍎🍊🍌
   | ^^^^^^^|^^^^^^^^^
   |        `----------- label
---'
]])
    file:close()
    os.remove(tmpname)

    code = "invalid utf8 \255"
    tmpname = write_temp_file(code)
    file = assert(io.open(tmpname, "r"))
    msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test_file_invalid_utf8")
      :label(1, #code):message("label")
      :source(file):render()
    )
    lu.assertEquals(msg, [[
Error: test_file_invalid_utf8
   ,-[ <unknown>:1:1 ]
   |
 1 | invalid utf8 ]] .. "\255" .. [[

   | ^^^^^^^|^^^^^^
   |        `-------- label
---'
]])
    file:close()
    os.remove(tmpname)
  end

  function TestFile.test_file_name()
    local code = "test content"
    local tmpname = write_temp_file(code)
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test_file_name")
      :label(1, 4):message("label")
      :file(tmpname):render()
    )
    os.remove(tmpname)
    lu.assertEquals(msg, [[
Error: test_file_name
   ,-[ ]] .. tmpname .. [[:1:1 ]
   |
 1 | test content
   | ^^|^
   |   `--- label
---'
]])
  end
end

local TestUnicode = {}
do
  local function test_case()
    -- it should has width 5+4+2+2+2+2+3=20
    -- code: "Test:café̄👋🏾🇺🇸🇨🇳👨‍🔧👨🏽‍❤️‍👨🏻end"
    return "Test:caf" .. utf8.char(0xE9, 0x304,
          0x1F44B, 0x1F3FE,
          0x1F1FA, 0x1F1F8,
          0x1F1E8, 0x1F1F3,
          0x1F468, 0x200D, 0x1F527,
          0x1F468, 0x1F3FD, 0x200D, 0x2764, 0xFE0F, 0x200D, 0x1F468, 0x1F3FB) ..
        "end"
  end
  function TestUnicode.test_width()
    local code = test_case()
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii())
      :title("Error", "test_unicode_width")
      :label(28, 30):message("end is here")
      :source(code):render()
    )
    lu.assertEquals(msg, [[
Error: test_unicode_width
   ,-[ <unknown>:1:1 ]
   |
 1 | Test:café̄👋🏾🇺🇸🇨🇳👨‍🔧👨🏽‍❤️‍👨🏻end
   |                    ^|^
   |                     `--- end is here
---'
]])
  end

  function TestUnicode.test_break_normal()
    local code = test_case()
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(29))
      :title("Error", "test_unicode_break")
      :label(28, 30):message("1")
      :source(code):render()
    )
    lu.assertEquals(msg, [[
Error: test_unicode_break
   ,-[ <unknown>:1:1 ]
   |
 1 | ...café̄👋🏾🇺🇸🇨🇳👨‍🔧👨🏽‍❤️‍👨🏻end
   |                  ^|^
   |                   `--- 1
---'
]])
  end

  function TestUnicode.test_break_1()
    local code = test_case()
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(26))
      :title("Error", "test_unicode_break")
      :label(28, 30):message("1")
      :source(code):render()
    )
    lu.assertEquals(msg, [[
Error: test_unicode_break
   ,-[ <unknown>:1:1 ]
   |
 1 | ...é̄👋🏾🇺🇸🇨🇳👨‍🔧👨🏽‍❤️‍👨🏻end
   |               ^|^
   |                `--- 1
---'
]])
  end

  function TestUnicode.test_break_2()
    local code = test_case()
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(25))
      :title("Error", "test_unicode_break")
      :label(28, 30):message("1")
      :source(code):render()
    )
    lu.assertEquals(msg, [[
Error: test_unicode_break
   ,-[ <unknown>:1:1 ]
   |
 1 | ...👋🏾🇺🇸🇨🇳👨‍🔧👨🏽‍❤️‍👨🏻end
   |              ^|^
   |               `--- 1
---'
]])
  end

  function TestUnicode.test_break_3()
    local code = test_case()
    local msg = remove_trailing(
      ariadne.report(1)
      :config(no_color_ascii():limit_width(24))
      :title("Error", "test_unicode_break")
      :label(28, 30):message("1")
      :source(code):render()
    )
    lu.assertEquals(msg, [[
Error: test_unicode_break
   ,-[ <unknown>:1:1 ]
   |
 1 | ...🇺🇸🇨🇳👨‍🔧👨🏽‍❤️‍👨🏻end
   |            ^|^
   |             `--- 1
---'
]])
  end
end

_G.TestColor = TestColor
_G.TestWrite = TestWrite
_G.TestLocLimit = TestLocLimit
_G.TestLineLimit = TestLineLimit
if not use_ref then
  if package.config:sub(1, 1) ~= "\\" then
    _G.TestFile = TestFile
  end
  _G.TestUnicode = TestUnicode
end

os.exit(lu.LuaUnit.run())
