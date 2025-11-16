# Project Structure

This document describes the technical architecture, data structures, and design decisions of the Ariadne Lua implementation.

## Quick Reference

- Language: Lua with UTF-8 support (tested against Lua 5.1/LuaJIT)
- Dependencies: 
  - `lua-utf8` library for UTF-8 operations (requires `utf8.widthlimit` for line width limiting)
  - `luaunit` for tests
  - Optional `luacov` for coverage
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
Report:render(cache)
  └─> RenderContext.new(id, pos, cache, labels, cfg)
      ├─ Group labels by source_id → SourceGroup[]
      ├─ Calculate line_no_width, ellipsis_width
      └─> RenderContext:render_header() + render_footer()
          └─> for each SourceGroup
              ├─> SourceGroup:collect_multi_labels()
              ├─> SourceGroup:render_reference()  -- ,-[ file.lua:line:col ]
              └─> SourceGroup:render_lines()
                  └─> for each line in range
                      ├─> LabelCluster.new()      -- Build cluster for this line
                      └─> LabelCluster:render()
                          ├─> render_line()       -- Source code with windowing
                          └─> render_arrows()     -- Label arrows + messages
```

### Three-Tier Architecture (Post-Refactor)

**RenderContext** (Top-level coordinator):
- Holds global rendering state: `line_no_width`, `ellipsis_width`
- Groups labels by source into `SourceGroup[]`
- Renders report header/footer and line numbers
- **Does not** perform line-level rendering

**SourceGroup** (Source file manager):
- Manages all labels for a single source file
- Encapsulates margin-related data: `multi_labels`, `multi_labels_with_message`
- Iterates over source lines and builds `LabelCluster` per line
- Renders margin symbols (vertical/horizontal bars)
- **Does not** access cluster internals directly

**LabelCluster** (Virtual row renderer):
- Represents a single rendered line (current: one cluster per physical line)
- Holds window bounds: `start_col`, `end_col`, `arrow_len`
- Renders source code, arrows, and messages for its labels
- **Self-contained**: computes all layout from injected parameters
- **Phase 3 ready**: designed to support multiple clusters per line

### Layer Independence

- `LabelCluster` does **not** hold references to `SourceGroup` or `RenderContext`
- Required data passed explicitly via constructor and `render()` parameters
- `SourceGroup` provides accessor methods for internal collections:
  - `:iter_margin_labels()`, `:iter_multi_labels()`, `:iter_labels()`
  - `:margin_len()`, `:get_source()`
- Encapsulation enforced through `@field private` annotations

## Key Data Structures

### `RenderContext`
Top-level rendering coordinator:
- `id`: Report source ID (for location calculation)
- `pos`: Report position (for location calculation)
- `groups`: Array of `SourceGroup` objects
- `line_no_width`: Maximum width of line numbers across all sources
- `ellipsis_width`: Display width of ellipsis character

**Responsibilities**:
- Group labels by source file
- Render report header (Error/Warning + message)
- Render line numbers via `:render_lineno()`
- Render footer (Help/Note sections)

### `SourceGroup`
Source file label manager:
- `src`: `Source` object (private)
- `labels`: All `LabelInfo` for this source (private)
- `multi_labels`: Multiline labels (private)
- `multi_labels_with_message`: Multiline labels with messages (private)
- `start_char`, `end_char`: Label span boundaries

**Responsibilities**:
- Collect and sort multiline labels
- Calculate reference location string
- Render reference header: `,-[ file.lua:123:45 ]`
- Render margin symbols (vbar, hbar, corner)
- Iterate over source lines and create `LabelCluster` instances

**Public accessors**:
- `:iter_margin_labels()`, `:iter_multi_labels()`, `:iter_labels()`
- `:margin_len()`, `:get_source()`, `:last_line_no()`

### `LabelCluster`
Virtual row rendering unit (one cluster per line in Phase 2):
- `line`: `Line` object (private)
- `line_no`: Display line number (private)
- `margin_label`: The primary margin label for this line (private)
- `line_labels`: Labels to render on this line (private)
- `arrow_len`, `start_col`, `end_col`: Window bounds (private)

**Responsibilities**:
- Compute window range via `calc_col_range()`
- Render source code line with optional ellipsis
- Render label arrows and messages

**Phase 3 extension**:
- `SourceGroup:render_lines()` will build multiple clusters per line
- Each cluster represents a "virtual row" with distinct label subset
- Margin symbols will connect across virtual rows

### `LabelInfo`
Internal label representation:
- `start_char`: 1-based char offset (inclusive)
- `end_char`: 1-based char offset (inclusive, `nil` for zero-width spans)
- `multi`: boolean, whether this is a multiline label
- `label`: reference to original `Label` object (has `message`, `color`, `priority`)

### `LineLabel`
Label positioned on a specific line:
- `col`: Display column where label appears
- `info`: Reference to `LabelInfo`
- `draw_msg`: Boolean, whether to draw message on this line

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

### `Line`
Pre-computed line metadata (part of `Source`):
- `offset`: 1-based char offset of line start in source
- `len`: character length (excluding newline)
- `byte_offset`: byte offset for `string.sub`
- `byte_len`: byte length (excluding newline)
- `newline`: boolean, whether line ends with `\n`

**Helper methods**:
- `:span()` - returns `(offset, offset + len - 1)`
- `:byte_span()` - returns `(byte_offset, byte_offset + byte_len - 1)`
- `:span_contains(char_pos)` - checks if position within line
- `:col(char_pos)` - converts character position to column (1-based)
- `:is_within_label(multi_labels)` - checks if line intersects multiline labels

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

#### 2. Layered Architecture with Clear Boundaries

**Three-tier separation** (implemented 2025-11-17):
- **RenderContext**: Global state + header/footer rendering
- **SourceGroup**: Per-source logic + margin rendering
- **LabelCluster**: Per-line rendering + window management

**Benefits**:
- Each layer encapsulates its own data (via `@field private`)
- No upward references: `LabelCluster` doesn't reference `SourceGroup`
- Data flows downward through explicit parameters
- Easy to extend: Phase 3 multi-cluster just modifies `SourceGroup:render_lines()`

**Parameter passing strategy**:
- Context objects (`RenderContext`, `SourceGroup`) passed to methods that need them
- Cluster-specific data (margin_label, line_labels) passed as parameters
- Avoids "context explosion" while maintaining encapsulation

#### 3. Simplified Margin Rendering
- Eliminated complex pointer comparisons and multi-stage filtering
- Removed no-op code (where `hbar` is set then immediately filtered away)
- Consolidated conditions using early returns and direct logic flow
- Encapsulated in `SourceGroup:render_margin()` with clear parameters

#### 3. No `continue` or `goto`
- All control flow uses nested `if-elseif-else` chains
- Maintains readability without Lua 5.2+ `goto` or multiple `return` points

#### 4. Tab Width Calculation
- Original (0-based): `tab_width - col % tab_width`
- This implementation (1-based): `tab_width - ((col - 1) % tab_width)`
- Equivalent forms verified with `tab_width = 4` across `col = 1, 2, 5, 8`

#### 5. Encapsulation via Accessor Methods
- `SourceGroup` fields marked `@field private` to prevent external access
- Public accessors provide controlled read-only access:
  - `:iter_margin_labels()` - iterate multiline labels with messages
  - `:iter_multi_labels()` - iterate all multiline labels
  - `:iter_labels()` - iterate all labels
  - `:margin_len()` - count of margin labels
  - `:get_source()` - access to Source object
- Maintains flexibility to change internal representation without breaking API

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

## Line Width Limiting (Implemented Feature – Phase 2)

### UTF-8 Width Calculation Dependency

The line width limiting feature depends on `utf8.widthlimit()` from luautf8:

**Function signature**:
```lua
utf8.widthlimit(s, i, j[, limit[, ambiwidth[, default]]])
```

**Parameters**:
- `s` (string): Input string
- `i` (integer): Start byte position (1-based)
- `j` (integer): End byte position (1-based)
- `limit` (integer, optional): Maximum display width
  - **Positive**: Truncate from front, return end position
  - **Negative**: Truncate from back, return start position (absolute value used)
  - **Omitted/nil**: Just measure width, return `j` and actual width
- `ambiwidth` (integer, optional): Width for ambiguous-width characters (1 or 2, default: 1)
- `default` (integer, optional): Width for unparseable characters (default: 1)

**Returns**:
- `pos` (integer): Truncation byte position, or `j` if just measuring
- `width` (integer): Actual display width consumed

**Example usage**:
```lua
-- Measure width (no limit parameter)
local pos, width = utf8.widthlimit("你好world", 1, 11)
-- Returns: pos=11, width=9  (total width of "你好world")

-- Truncate from front (keep prefix)
local pos, width = utf8.widthlimit("hello world", 1, 11, 5)
-- Returns: pos=5, width=5  (can truncate at byte 5, "hello")

-- Truncate from back (keep suffix)
local pos, width = utf8.widthlimit("/path/to/file.lua", 1, 17, -8)
-- Returns: pos=10, width=8  (start at byte 10, "file.lua")
```

**Use case**: This unified function handles both:
1. **Measuring**: Calculate label width to determine available space for context
2. **Truncating**: Find safe truncation points for prefix/suffix with ellipsis

### Soft Limit Strategy (Recap)

`line_width` is treated as a **soft limit**:

- **Priority 1**: Always display core diagnostic information (label position, message)
- **Priority 2**: Apply truncation to context (file paths, code lines)
- **Priority 3**: If core information exceeds `line_width`, ignore the limit

**Rationale**: Users may resize terminal after viewing output; forcing truncation of essential information would require recompilation.

**Implementation approach** (completed in Phase 2):
- Reference headers: Truncate file path from start, keep filename + location
- Code lines: Show local context around labels with ellipsis
- Messages: Always display fully (no truncation or wrapping)
- Tab characters in file paths: Normalized to spaces before width calculation

## Cluster & Virtual Row Design (Phase 3)

### Motivation
Multiple distant labels on very long lines create unreadable horizontal spans. Clusters partition labels so each virtual row shows a focused subset with balanced context, improving clarity without losing messages.

### New Abstractions
- `LabelCluster`: Logical grouping of labels rendered together; holds aggregated window metrics.
- `VirtualRow`: A rendering pass for one cluster; shares physical line number with siblings.

### Planned Data Structure Fields
`LabelCluster`:
- `labels`: array of `LabelInfo`
- `min_col`, `max_col`: display column bounds after width expansion
- `window_start_col`, `window_end_col`: cropping window from `calc_col_range`
- `needs_prefix_ellipsis`, `needs_suffix_ellipsis`: booleans
- `row_index`: virtual row ordinal

`SourceGroup` (refactor):
- `clusters_per_line`: { line_no => { cluster1, cluster2, ... } }
- `multi_labels_with_message`, `multi_labels`: migrated under instance scope
- Methods: `build_clusters_for_line(line_no)`, `iter_virtual_rows(line_no)`

### Parameter Hierarchy Refactor
- Report-level (`RenderCtx`): config, `line_no_width`, glyph tables, ellipsis width.
- Group-level (`GroupCtx`): source-specific caches, collections of labels.
- Cluster-level (`ClusterCtx`): cluster window bounds, local label list, ellipsis flags.
- Reduces long argument lists in `render_line`, `render_arrows`, etc.

### Greedy Clustering Heuristic (Initial)
1. Sort labels by start column.
2. Initialize first cluster with first label.
3. For each subsequent label:
    - Compute merged minimal width = span(min_col, new_end) + arrow/message overhead.
    - If merged width > `line_width` AND distance from previous label > `context_gap` (e.g. 8 display columns) → start new cluster.
    - Else append to current cluster.
4. After clusters built, apply existing `calc_col_range` using cluster-wide min/max and max label width.

### Window Reuse
`calc_col_range` remains authoritative; cluster provides aggregated metrics so no new window algorithm required.

### Soft Limit Interaction
If a cluster’s minimal meaningful width (labels + context + messages) exceeds `line_width`, exceed soft limit instead of truncating essential data.

### Margin Continuity Across Virtual Rows
Maintain per-line active vertical bars; re-emit them in subsequent virtual rows to visually connect related multiline labels.

### Testing Matrix (Planned)
- Two far labels → two clusters
- Three labels forming two clusters
- Close labels remain one cluster
- CJK wide labels across clusters
- Cluster exceeding soft limit still shows full messages
- Compact mode may merge clusters (verify behavior)

### Phase 4 Preview: Forced Multiline / Intra-Cluster Splitting
Extremely wide single spans inside a cluster can convert to multiline arrows (`label.multi = true`) or sub-clusters. Cluster isolation simplifies transformation without impacting unrelated labels.

