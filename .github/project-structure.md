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
- Coverage: Currently at 100% test coverage (all reachable code covered, 83 tests passing)

## File Structure

- **`ariadne.lua`**: All runtime code (~1650 lines), structured into sections:
  - **Classes**: `Cache`, `Line`, `Source` (source text parsing and line indexing)
  - **CharSet**: `Characters.unicode` and `Characters.ascii` (rendering glyphs)
  - **Config**: Configuration tables
  - **Labels**: `Label` class for marking spans with messages and colors
  - **Reports**: `Report` class for building diagnostic messages
  - **Rendering**: Core rendering functions
  - **Public API**: Builder-style helpers (`Report.build`, `Label.new`, `Source.new`)

- **`test.lua`**: Exhaustive regression suite (~1400 lines). Snapshots rendered diagnostics and exercises edge cases (multi-byte chars, zero-width spans, compact mode, multiline labels, etc.). All tests produce pixel-perfect diagnostic output.

- **`serpent.lua`** and **`luaunit.lua`**: Vendored dependencies used by the tests; remain untouched unless upgrading.

## Rendering Pipeline (Writer-Orchestrated)

```
Report:render(cache)
  ├─> context_new(id, cache, labels, cfg)
  │   ├─ Group labels by source_id → SourceGroup[]
  │   ├─ Calculate line_no_width, ellipsis_width
  │   └─> Create Writer with config and line_no_width
  ├─> Writer:render_header(kind, code, message)
  ├─> for each SourceGroup
  │   ├─ sg_collect_multi_labels(group)
  │   ├─ Writer:render_reference(idx, group, report_id, report_pos)
  │   ├─ Writer:render_empty_line()
  │   ├─ Writer:render_lines(group)
  │   │  └─> for each line in range
  │   │      ├─> clusters = lc_assemble_clusters(line, line_no, group, ...)
  │   │      └─> for each cluster in clusters  -- Phase 3: Multiple virtual rows
  │   │          ├─> lc_calc_col_range(cluster, group, ...)
  │   │          └─> Writer:render_label_cluster(cluster, group)
  │   │              ├─> Writer:render_line(...)
  │   │              └─> Writer:render_arrows(...)
  │   └─> Writer:render_empty_line()
  └─> Writer:render_footer(#groups, helps, notes)
```

### Writer-Orchestrated Architecture

**Writer** (Top-level orchestrator):
- Holds global rendering state: `config`, `line_no_width`, `ellipsis_width`
- Orchestrates all rendering via methods: `render_header`, `render_reference`, `render_lines`, `render_footer`
- Manages color state and output buffer
- **Does not** hold references to SourceGroup/LabelCluster structures
- All data passed via parameters

**SourceGroup** (Per-source data container):
- Encapsulates source-specific data: `src`, `labels`, `multi_labels`, `multi_labels_with_message`
- Provides C-style functions: `sg_new`, `sg_add_label_info`, `sg_collect_multi_labels`, `sg_last_line_no`, `sg_calc_location`
- **Does not** perform rendering directly (Writer handles output)
- **Does not** hold references to Writer or LabelCluster

**LabelCluster** (Virtual row/window manager):
- Represents a single rendered cluster (Phase 3: supports multiple clusters per physical line)
- Holds window bounds: `start_col`, `end_col`, `arrow_len`, `min_col`, `max_msg_width`
- Holds cluster-specific data: `line`, `line_no`, `line_labels`, `margin_label`
- Created via `lc_assemble_clusters` (builds all clusters for a line)
- Window calculated via `lc_calc_col_range` (per-cluster windowing)
- **Self-contained**: computes all layout from injected parameters
- **Clustering complete**: min/max width tracking, order-first sorting, margin exclusion logic

### Layer Independence

- **Writer** only holds global parameters, passes all data via method parameters
- **LabelCluster** does not reference SourceGroup or Writer, all data passed explicitly
- **SourceGroup** exposes data only via C-style functions (sg_*, not methods)
- Data flows: Report → context_new → Writer + SourceGroup[] → Writer orchestrates rendering
- Encapsulation enforced through pure functions and explicit parameter passing

## Key Data Structures

### `Writer`
Top-level rendering orchestrator:
- Array part: Output buffer (array of strings)
- `config`: Rendering configuration (Config object)
- `line_no_width`: Maximum width of line numbers across all sources
- `ellipsis_width`: Display width of ellipsis character (computed from config.char_set)
- `cur_color` / `cur_color_code`: Current foreground color state

**Key Methods**:
- `render_header(kind, code, message)`: Render report header
- `render_reference(idx, group, report_id, report_pos)`: Render file reference header
- `render_lines(group)`: Iterate lines and render clusters
- `render_label_cluster(cluster, group)`: Render one cluster's line and arrows
- `render_line(...)`: Render source code with windowing
- `render_arrows(...)`: Render label arrows and messages
- `render_margin(...)`: Render margin symbols (vbar/hbar/corner)
- `render_lineno(line_no, is_ellipsis)`: Render line number
- `render_footer(group_count, helps, notes)`: Render help/note sections

### `SourceGroup`
Per-source data container:
- `src`: `Source` object
- `labels`: All `LabelInfo` for this source
- `multi_labels`: Multiline labels (populated by sg_collect_multi_labels)
- `multi_labels_with_message`: Multiline labels with messages (populated by sg_collect_multi_labels)
- `start_char`, `end_char`: Label span boundaries

**C-style Functions** (not methods):
- `sg_new(src, info)`: Create new SourceGroup with first label
- `sg_add_label_info(group, info)`: Add label to existing group
- `sg_collect_multi_labels(group)`: Collect and sort multiline labels
- `sg_last_line_no(group)`: Get last line number in group
- `sg_calc_location(group, ctx_id, ctx_pos, cfg)`: Calculate location string (line:col)

**Note**: SourceGroup has no methods (`:` syntax), only C-style functions that take `group` as first parameter

### `LabelCluster`
Virtual row/window manager:
- `line`: `Line` object (physical source line)
- `line_no`: Line number for this cluster
- `line_labels`: Labels to render in this cluster (inline + end-with-message labels)
- `margin_label`: The primary margin label for this cluster (first multi in sorted order)
- `arrow_len`: Maximum arrow length (rightmost label end + arrow spacing)
- `min_col`: Leftmost label start column
- `max_msg_width`: Maximum message width across all labels
- `start_col`, `end_col`: Window bounds (computed by `lc_calc_col_range`)

**Clustering Algorithm** (Phase 3):
- Sort labels: `order < col < start_char` (start_char descending for tie-breaking)
- Track `min_start_width` and `max_end_width` during iteration
- Split when `(max_end_width - min_start_width) + message_width > limit_width`
- Select first `multi` label as `margin_label`, exclude from `line_labels` unless it's `end` with message

**C-style Functions**:
- `lc_new(line, line_no)`: Create empty cluster
- `lc_assemble_clusters(line, line_no, group, line_no_width, cfg)`: Build clusters from line labels
- `lc_calc_col_range(cluster, group, line_no_width, ellipsis_width, cfg)`: Calculate window bounds

**Future**: Multiple clusters per physical line (Phase 3 complete, ready for expansion)

**C-style Functions**:
- `lc_new(idx, line, group, cfg)`: Create cluster for a line
- `lc_calc_col_range(cluster, group, line_no_width, ellipsis_width, cfg)`: Calculate window bounds
- `lc_get_highlight(cluster, col, group)`: Get highlight label at column
- `lc_get_vbar(cluster, col, row)`: Get vbar label at column/row
- `lc_get_underline(cluster, col, cfg)`: Get underline label at column
- `lc_is_margin_label(cluster, info)`: Check if label is margin label
- `get_margin_label(line, group)`: Select margin label for line
- `collect_multi_labels_in_line(cluster, group)`: Collect multiline labels
- `collect_labels_in_line(cluster, group, attach)`: Collect all labels for line

**Phase 3 extension**:
- `Writer:render_lines()` will build multiple clusters per line
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

#### 2. Writer-Orchestrated Architecture with Clear Boundaries

**Three-layer separation** (Writer-orchestrated, implemented 2025-11-18):
- **Writer**: Top-level orchestrator with rendering methods
- **SourceGroup**: Per-source data container with C-style functions
- **LabelCluster**: Per-line window manager with C-style functions

**Benefits**:
- Each layer has clear, single responsibility
- No upward references: LabelCluster and SourceGroup don't reference Writer
- All data flows via explicit parameter passing
- Easy to extend: Phase 3 multi-cluster just modifies cluster creation logic in Writer:render_lines()
- C-migration ready: Writer becomes C orchestrator, SourceGroup/LabelCluster become C structs + functions

**Parameter passing strategy**:
- Writer holds global state (config, line_no_width, ellipsis_width)
- SourceGroup/LabelCluster passed as parameters to functions that need them
- No implicit context, all dependencies explicit
- Avoids "context explosion" while maintaining encapsulation

#### 3. Simplified Margin Rendering
- Eliminated complex pointer comparisons and multi-stage filtering
- Removed no-op code (where `hbar` is set then immediately filtered away)
- Consolidated conditions using early returns and direct logic flow
- Encapsulated in `Writer:render_margin()` with clear parameters

#### 4. No `continue` or `goto`
- All control flow uses nested `if-elseif-else` chains
- Maintains readability without Lua 5.2+ `goto` or multiple `return` points

#### 4. Tab Width Calculation
- Original (0-based): `tab_width - col % tab_width`
- This implementation (1-based): `tab_width - ((col - 1) % tab_width)`
- Equivalent forms verified with `tab_width = 4` across `col = 1, 2, 5, 8`

#### 5. Encapsulation via C-style Functions
- SourceGroup and LabelCluster use C-style functions (not methods)
- All functions take the structure as first parameter (e.g., `sg_new(src, info)`, `lc_new(idx, line, group, cfg)`)
- No hidden state or implicit context
- Clear data flow: caller passes all required parameters
- Easy to port to C: functions map directly to C functions taking struct pointers

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

### Bug Fixes (2025-11-23): Virtual Line Windowing with Multiline Labels

During C migration, three subtle bugs were discovered in the multiline label rendering logic when combined with line width limiting (virtual line windowing). All three bugs involve edge cases where multiline labels interact with window truncation.

#### Bug 1: Line 727 – Margin Label Line-End Extension in Virtual Rows

**Location**: `lc_assemble_clusters()`, line 724-730:

**Original code**:
```lua
if ll.info.multi then
    if ll.draw_msg then
        end_col = lc.line.len + (line.newline and 1 or 0)
    end
    if not lc.margin_label then lc.margin_label = ll end
end
```

**Problem**: 
- Multiline labels with messages (`draw_msg = true`) always extended to line end
- In virtual rows (with line width limits), margin labels should NOT extend beyond the window
- But non-margin multiline labels still need to extend to show proper arrow routing

**Root cause**:
- Code checked `ll.draw_msg` before setting `lc.margin_label`
- Thus couldn't distinguish "is this label the margin label?" at decision time

**Fix**:
```lua
if ll.info.multi then
    if not lc.margin_label then lc.margin_label = ll end
    if (not cfg.line_width or lc.margin_label ~= ll) and ll.draw_msg then
        end_col = lc.line.len + (line.newline and 1 or 0)
    end
end
```

**Solution**:
1. Set `margin_label` first (line 725)
2. Only extend to line end when:
   - No line width limit (`not cfg.line_width`), OR
   - Current label is NOT the margin label (`lc.margin_label ~= ll`)
3. Margin labels in virtual rows stay within window bounds

**Test case**: `TestLineWindowing.test_multiline` – Verifies margin label doesn't extend beyond window

---

#### Bug 2: Line 736 – Incorrect `min_col` Calculation Using Absolute Offset

**Location**: `lc_assemble_clusters()`, line 735-737:

**Original code**:
```lua
lc.min_col = math.min(lc.min_col or ll.info.start_char, ll.info.start_char)
```

**Problem**:
- `ll.info.start_char` is an **absolute character offset** in the source (e.g., char 150 in file)
- `min_col` should be a **column number** relative to current line (e.g., column 5)
- For inline labels on same line: `start_char - line.offset` happens to equal column number (bug hidden)
- For multiline labels: `start_char` from previous lines causes completely wrong `min_col`

**Root cause**:
- Direct use of `start_char` without coordinate conversion
- Multiline labels have `ll.col` already computed (relative column)
- Inline labels need conversion via `line_col(line, start_char)`

**Fix**:
```lua
local min_col = ll.info.multi and ll.col or
    line_col(line, ll.info.start_char)
lc.min_col = math.min(lc.min_col or min_col, min_col)
```

**Solution**:
1. For multiline labels: Use `ll.col` (already relative to current line)
2. For inline labels: Convert via `line_col(line, start_char)` (absolute → relative)
3. Use converted `min_col` for tracking cluster bounds

**Impact**: This bug could cause negative window positions or incorrect context rendering when multiline labels span across multiple lines.

**Test case**: `TestLineWindowing.test_multiline` – Verifies correct column calculation for multiline labels

---

#### Bug 3: Line 985 – Arrow Ellipsis Padding Logic Too Broad

**Location**: `Writer:render_arrows()`, line 982-989:

**Original code**:
```lua
if lc.start_col > 1 then
    W:padding(W.ellipsis_width, ll.draw_msg and " " or draw.hbar)
end
```

**Problem**:
- Logic: `ll.draw_msg == true` → fill with space; `ll.draw_msg == false` → fill with `hbar`
- `draw_msg = false` only for multiline **start** labels (set in `collect_multi_labels` line 620)
- Missing case: **Margin label end** with message (`draw_msg = true`) also needs `hbar` fill

**Root cause**:
Understanding `draw_msg` semantics:
```lua
-- In collect_multi_labels (line 616-626)
if line_contains(line, info.start_char) then
    ll = { col = ..., draw_msg = false }  -- Start: no message here
elseif info.end_char and line_contains(line, info.end_char) then
    ll = { col = ..., draw_msg = true }   -- End: show message here
end
```

So:
- `draw_msg = false` ⟺ Multiline start (has hbar routing back to margin)
- `draw_msg = true` ⟺ Inline labels OR multiline end
- **Margin label end** has `draw_msg = true` BUT also needs `hbar` under ellipsis

**Why margin end needs hbar**:
- Visual continuity: hbar starts from before ellipsis, extends to margin
- Without hbar fill: gap appears between ellipsis and margin arrow
- Only applies when `lc.start_col > 1` (window was truncated with ellipsis)

**Fix**:
```lua
if lc.start_col > 1 then
    local a = " "
    if ll == lc.margin_label or not ll.draw_msg then
        a = draw.hbar
    end
    W:padding(W.ellipsis_width, a)
end
```

**Solution**:
Two conditions for hbar fill:
1. `ll == lc.margin_label` – Current label is the margin label (new condition)
2. `not ll.draw_msg` – Multiline start label (original condition)

**Why this works**:
- **Margin start**: `draw_msg = false` → covered by condition 2
- **Margin end**: `ll == lc.margin_label` → covered by condition 1
- **Other inline/multiline**: Neither condition → fills with space

**Note on "margin without message"**: 
If margin label has no message, it has `draw_msg = false` (start) or filtered out (end), so never enters the arrow rendering loop (`if ll.draw_msg` guard at line ~975). Thus no special handling needed.

**Test case**: `TestLineWindowing.test_multiline` – Verifies correct ellipsis padding for margin labels

---

**Common theme**: All three bugs involve the interaction between:
- Multiline label state tracking (`margin_label`, `draw_msg`)
- Coordinate systems (absolute `start_char` vs. relative `col`)
- Virtual row windowing (line width limits triggering ellipsis rendering)

**Discovery context**: Found during C port when carefully tracing through `render_arrows()` and `lc_assemble_clusters()` logic. The bugs were latent in the Lua implementation but only triggered by specific combinations of:
- Long lines with width limits
- Multiline labels spanning the windowed region
- Labels positioned as margin labels

**Test coverage**: All three bugs are verified by `TestLineWindowing.test_multiline`, added 2025-11-23.

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


### Cluster & Virtual Row Design (Phase 3)

#### Motivation
Multiple distant labels on very long lines create unreadable horizontal spans. Clusters partition labels so each virtual row shows a focused subset with balanced context, improving clarity without losing messages.

#### New Abstractions
- `LabelCluster`: Logical grouping of labels rendered together; holds aggregated window metrics.
- `VirtualRow`: A rendering pass for one cluster; shares physical line number with siblings.

#### Planned Data Structure Fields
`LabelCluster`:
- `line_labels`: subset of labels
- `min_col`, `max_col`: display column bounds after width expansion
- `window_start_col`, `window_end_col`: cropping window from `lc_calc_col_range`
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

