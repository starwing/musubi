# Project Structure

This document describes the technical architecture, data structures, and design decisions of the Ariadne Lua implementation.

## Quick Reference

- Language: Lua with UTF-8 support (tested against Lua 5.1/LuaJIT)
- Dependencies: `lua-utf8` library for UTF-8 operations, `luaunit` for tests, optional `luacov` for coverage
- Entry points: `ariadne.lua` exports the public API
- Tests: run `lua test.lua` from the project root
- Coverage: Currently at 100% test coverage (all reachable code covered)

## File Structure

- **`ariadne.lua`**: All runtime code (~1500 lines), structured into sections:
  - **Classes**: `Cache`, `Line`, `Source` (source text parsing and line indexing)
  - **CharSet**: `Characters.unicode` and `Characters.ascii` (rendering glyphs)
  - **Config**: Configuration tables
  - **Labels**: `Label` class for marking spans with messages and colors
  - **Reports**: `Report` class for building diagnostic messages
  - **Rendering**: Core rendering functions
  - **Public API**: Builder-style helpers (`Report.build`, `Label.new`, `Source.new`)

- **`test.lua`**: Exhaustive regression suite (~1400 lines). Snapshots rendered diagnostics and exercises edge cases (multi-byte chars, zero-width spans, compact mode, multiline labels, etc.). All tests produce pixel-perfect diagnostic output.

- **`serpent.lua`** and **`luaunit.lua`**: Vendored dependencies used by the tests; remain untouched unless upgrading.

## Rendering Pipeline

```
Report:render(source)
  └─> compute_source_groups()     -- Group labels by source_id and char spans
      └─> render_report(W, ...)   -- Main rendering loop
          ├─> render_header(W, ...) -- Output: ,-[ file.lua:line:col ]
          ├─> (for each source line)
          │   ├─> render_margin(W, ...)   -- Output: left margin symbols (vbar, hbar, corner)
          │   ├─> render_line(W, ...)     -- Output: line number + source code
          │   ├─> render_arrows(W, ...)   -- Output: label arrows (^^^, |, ,->)
          │   └─> render_messages(W, ...) -- Output: label messages with colors
          └─> render_notes(W, ...)  -- Output: Help:/Note: sections
```

## Key Data Structures

### `Line`
Pre-computed line metadata:
- `offset`: 1-based char offset of line start in source
- `len`: character length (excluding newline)
- `byte_offset`: byte offset for `string.sub`
- `byte_len`: byte length (excluding newline)
- `newline`: boolean, whether line ends with `\n`

### `LabelInfo`
Internal label representation during rendering:
- `start_char`: 1-based char offset (inclusive)
- `end_char`: 1-based char offset (inclusive, `nil` for zero-width spans)
- `multi`: boolean, whether this is a multiline label
- `label`: reference to original `Label` object (has `message`, `color`, `priority`)

### `Config`
Plain table with fields:
- `compact`: boolean (default false) - compact arrow spacing
- `tab_width`: integer (default 4)
- `char_set`: "unicode" or "ascii" (default "unicode")
- `index_type`: "char" or "byte" (default "char")
- `color`: function or `false` (default false = no color)
- `label_attach`: "start" or "middle" (default "middle")
- `multiline_arrows`: boolean (default true)
- `cross_gap`: boolean (default false)
- `underlines`: boolean (default true)

## Key Design Decisions

### Source Handling
- Pre-computes both character and byte offsets so the renderer can switch between `char` and `byte` index types at runtime
- Uses 1-based indexing (Lua convention) vs Rust's 0-based
- Uses closed intervals `[start, end]` (both inclusive) vs Rust's half-open `[start, end)`
- Empty spans represented as `(pos, nil)` where `end_char = nil`, equivalent to Rust's `pos..pos`
- Line lengths exclude newlines (for simplicity), but `line.len + (line.newline and 1 or 0)` recovers Rust's `line.len()`

### Architectural Improvements Over Rust Original

#### 1. Flattened Rendering Loops (O(n) vs O(n²))

**Original Rust**: Nested loops `for col in 0..len { for i in 0..col+1 { ... } }`

**This implementation**: Single loop `for info in multi_labels { ... }` with carefully scoped variables

**Key insight**: The inner loop only affects output when `i == col` (due to `!is_parent` filters). By making each `info` correspond to one output column, the inner loop becomes redundant.

**Variable scoping strategy**:
- `vbar`, `corner`: Reset per iteration (local variables) - analogous to resetting per `col`
- `hbar`, `margin_ptr`: Preserved across iterations (outer variables) - analogous to accumulating in inner loop

**Equivalence verified**: All tests pass, output is pixel-perfect.

#### 2. Simplified Margin Rendering
- Eliminated complex pointer comparisons and multi-stage filtering
- Removed no-op code (where `hbar` is set then immediately filtered away)
- Consolidated conditions using early returns and direct logic flow

#### 3. No `continue` or `goto`
- All control flow uses nested `if-elseif-else` chains
- Maintains readability without Lua 5.2+ `goto` or multiple `return` points

#### 4. Tab Width Calculation
- Original (0-based): `tab_width - col % tab_width`
- This implementation (1-based): `tab_width - ((col - 1) % tab_width)`
- Equivalent forms verified with `tab_width = 4` across `col = 1, 2, 5, 8`

### Index Type Conversions

Original implementation uses 0-based half-open ranges: `span.start..span.end` means `[start, end)`.

This implementation uses 1-based closed ranges: `start_char, end_char` means `[start, end]`.

**Conversion rules** (from reference implementation):
- Original `start` → This `start + 1` (shift to 1-based)
- Original `end` → This `end` (because original's `end` is exclusive, this is inclusive)
- Empty span: Original `idx..idx` → This `(idx + 1, nil)`

**Conversion table**:

| Concept              | Original (0-based, half-open)   | This implementation (1-based, closed)            |
| -------------------- | ------------------------------- | ------------------------------------------------ |
| Single char at pos 0 | `0..1`                          | `(1, 1)`                                         |
| Empty span at pos 5  | `5..5`                          | `(6, nil)`                                       |
| Range [10, 20)       | `10..20`                        | `(11, 20)`                                       |
| Line offset          | `line.offset()` returns 0-based | `line.offset` is 1-based                         |
| String slicing       | `s[start..end]`                 | `s:sub(byte_offset, byte_offset + byte_len - 1)` |

**Critical gotcha**: When converting `end_char or start_char - 1`:
- Empty span: `end_char == nil`, so `start_char - 1` represents original's `start..start`
- Non-empty: `end_char` is the last character (inclusive), matching original's `end - 1`

### Tab Width Calculation (1-based correction)

**Original** (0-based col):
```rust
let width = tab_width - col % tab_width;
```

**This implementation** (1-based col):
```lua
local width = cfg.tab_width - ((col - 1) % cfg.tab_width)
```

**Verification table** (tab_width = 4):

| col (1-based) | col-1 (0-based equiv) | Result |
| ------------- | --------------------- | ------ |
| 1             | 0                     | 4      |
| 2             | 1                     | 3      |
| 5             | 4                     | 4      |
| 8             | 7                     | 1      |

### UTF-8 Handling
- Relies on `lua-utf8` library (compatible with Lua 5.1+)
- Only handles `\n` newlines (not Unicode line separators like U+2028)
- Rationale: Simplicity and cross-language consistency (not all languages follow Unicode newline rules)

### Rendering Logic
- Glyph tables (`Characters.unicode` / `Characters.ascii`) provide rendering symbols
- Color system uses function-based callback for flexibility
- Writer abstraction (`W:label()`, `W:use_color()`) encapsulates output buffering and color state

## Challenging Coverage Cases

### Line 1341: `a = draw.uarrow` in compact mode

**Location**: `render_arrows()`, line 1339-1341:
```lua
elseif vbar.info.multi and row == 1 and cfg.compact then
    a = draw.uarrow
end
```

**Why this is hard to cover**:

This line requires a very specific combination of conditions that appear contradictory at first:

1. **`vbar` exists AND `col ~= ll.col`** (line 1326 condition)
   - Key insight: `ll` is the **outer loop variable** (from `for row, ll in ipairs(line_labels)`)
   - `vbar` is returned by `get_vbar(col, row, margin_label, line_labels)`
   - These can be **different labels** from the same `line_labels` array!

2. **`is_hbar = false`** (line 1319 definition):
   ```lua
   local is_hbar = (col > ll.col) ~= ll.info.multi or
       ll.draw_msg and col > ll.col
   ```
   - For `ll.info.multi = true`, this becomes:
     `is_hbar = (col > ll.col) ~= true OR (ll.draw_msg AND col > ll.col)`
   - For `is_hbar = false`, we need:
     - `(col > ll.col) == true` AND `NOT (ll.draw_msg AND col > ll.col)` ← **Contradiction!**
     - OR `col <= ll.col` AND `NOT ll.draw_msg` ← **This works!**

3. **`vbar.info.multi = true`** (the vbar label must be multiline)
4. **`row == 1`** (first arrow row)
5. **`cfg.compact = true`** (compact mode)
6. **`vbar` must exist via `get_vbar(col, row, margin_label, line_labels)`**

**The winning strategy**:

To satisfy `col <= ll.col` AND `col == vbar.col`, we need **3 multiline labels**:

- **Label A** (margin_label): Highest column (e.g., col=4), excluded from `line_labels` by `collect_multi_labels_in_line`
- **Label B** (vbar): Lower column (e.g., col=1), included in `line_labels`, matches `get_vbar(1, ...)`
- **Label C** (ll): Middle column (e.g., col=2), lowest order (processed first in outer loop)

When `row=1` (processing Label C) and `col=1`:
- `ll = Label C` (outer loop), `ll.col = 2`
- `vbar = Label B` (from `get_vbar(1, ...)`), `vbar.col = 1`
- `col (1) <= ll.col (2)` ✓ → `is_hbar = false`
- `col (1) ~= ll.col (2)` ✓ → enters line 1326 branch
- `vbar.info.multi = true` ✓
- `cfg.compact = true` ✓
- Line 1341 executes!

**Test implementation**: See `test_uarrow` in `test.lua`.

### Line 1043: `xbar` in margin with cross_gap disabled

**Location**: `render_margin()`, line 1043-1044:
```lua
elseif vbar and hbar and not cfg.cross_gap then
    W:use_color(vbar.label.color):label(draw.xbar):compact(draw.hbar)
```

**Why this is hard to cover**:

This line renders a cross symbol (`+` in ASCII, `┼` in Unicode) in the margin when two multiline labels intersect. The challenge is that `vbar` and `hbar` are set in **different iterations** of the loop.

**Key variable scoping**:
```lua
local hbar, margin_ptr  -- Outer variables, persist across iterations
for mli, info in ipairs(multi_labels_with_message) do
    local vbar, corner  -- Local variables, reset each iteration
    -- ...
end
```

**Original Rust code bug**:

The original implementation had this sequence:
```rust
// Set hbar for margin_ptr rows
if let (Some((margin, _is_start)), true) = (margin_ptr, is_line) {
    if !is_col && !is_limit {
        hbar = hbar.or(Some(margin.label));
    }
}

// Immediately filter out the hbar we just set (BUG!)
hbar = hbar.filter(|l| {
    margin_label.as_ref().map_or(true, |margin| !std::ptr::eq(margin.label, *l))
    || !is_line
});
```

This was **no-op code**: it set `hbar = margin.label`, then immediately filtered it out when `is_line = true` and `margin.label == hbar`. The second filter should have checked `&& !is_limit` to preserve `hbar` for all columns except the last.

**The fix** (lines 1039-1041, 1063):

```lua
-- Line 1039-1041: Set hbar for margin_ptr rows
if (not hbar) and margin_ptr and is_line and info ~= margin_ptr then
    hbar = margin_ptr
end

-- Line 1063: Clear hbar at the last column (show arrow instead)
if hbar and (not is_line or hbar ~= margin_ptr) then
    W:use_color(hbar.label.color):label(draw.hbar):compact(draw.hbar):reset()
elseif margin_ptr and is_line then
    W:use_color(margin_ptr.label.color):label(draw.rarrow):compact ' ':reset()
```

**How line 1043 gets triggered**:

When `margin_ptr` is set and we're on a line where it ends (`is_line = true`):
- **Iteration 1** (margin_ptr label): Sets `vbar`, `corner`, `hbar` for itself → outputs `corner`
- **Iteration 2** (another multiline label): 
  - Sets `vbar = info` (this label passes through)
  - Line 1039 triggers: `hbar = margin_ptr` (inherited from previous context)
  - Now we have: `vbar != nil`, `hbar != nil`, `corner == nil`, `cfg.cross_gap = false`
  - Line 1043 executes: output `xbar` (cross symbol)

**Test scenario** (`test_margin_xbar`):

```lua
-- Source: "apple\norange\nbanana\nstrawberry"
-- Label outer: (1, 14), chars 1-14, spans lines 1-2, order=0 (margin_label)
-- Label inner: (7, 21), chars 7-21, spans lines 2-3, order=1

-- On line 2, margin rendering:
--   margin_ptr = outer (ends on this line)
--   Iteration 1 (outer): outputs corner ','
--   Iteration 2 (inner): 
--     - vbar = inner (passes through)
--     - hbar = outer (from line 1039)
--     - Outputs xbar '+' at line 1043
-- Result: ",-+-> orange"
```

**Test implementation**: See `test_margin_xbar` in `test.lua`.

## Code Examples

### Basic Error Report
```lua
local report = ariadne.Report.build("Error", 1, 5)
    :set_message("can't compare apples with oranges")
    :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
    :finish()
local output = report:write_to_string(ariadne.Source.new("apple == orange"))
```

### Multi-label Layout
See `TestWrite.test_multiple_labels_same_span` in `test.lua` for overlapping arrow output expectations.

### Color Support
```lua
local function color_fn(category)
    if category == "error" then return "\27[31m" end  -- Red
    if category == "reset" then return "\27[0m" end   -- Reset
    return nil
end
local cfg = ariadne.Config.new()
cfg.color = color_fn
report:with_config(cfg):render(source)
```
