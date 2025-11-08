This repository is a Lua implementation of the Ariadne diagnostics renderer. Originally ported from the Rust `ariadne` library, it now serves as the primary implementation with architectural improvements for performance and clarity. The Lua version is idiomatic to Lua 5.1+ while maintaining compatibility with the original diagnostic output format.

Quick context
- Language: Lua with UTF-8 support (tested against Lua 5.1/LuaJIT).
- Dependencies: `lua-utf8` library for UTF-8 operations, `luaunit` for tests, optional `luacov` for coverage.
- Entry points: `ariadne.lua` exports the public API (see "Public API" section below).
- Tests: run `lua test.lua` from the project root once `luaunit` (and `luacov` if desired) are on `package.path`.
- Coverage: Currently at 98% test coverage. See `luacov.report.out` for coverage details.

High-level architecture (what to know fast)
- `ariadne.lua` contains all runtime code (~1500 lines), structured into sections:
  - **Classes**: `Cache`, `Line`, `Source` (source text parsing and line indexing)
  - **CharSet**: `Characters.unicode` and `Characters.ascii` (rendering glyphs)
  - **Config**: Configuration tables with fields like `compact`, `tab_width`, `char_set`, `index_type`, `color`, `label_attach`, `multiline_arrows`, `cross_gap`, `underlines`
  - **Labels**: `Label` class for marking spans with messages and colors
  - **Reports**: `Report` class for building diagnostic messages
  - **Rendering**: Core rendering functions (see "Rendering pipeline" section)
  - **Public API**: Builder-style helpers (`Report.build`, `Label.new`, `Source.new`)
  
- `test.lua` is the exhaustive regression suite (~1050 lines). It snapshots rendered diagnostics and exercises edge cases (multi-byte chars, zero-width spans, compact mode, multiline labels, etc.). All tests produce pixel-perfect diagnostic output.

- `serpent.lua` and `luaunit.lua` are vendored dependencies used by the tests; they should remain untouched unless upgrading.

Rendering pipeline (execution flow)
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

Key data structures
- **`Line`**: Pre-computed line metadata
  - `offset`: 1-based char offset of line start in source
  - `len`: character length (excluding newline)
  - `byte_offset`: byte offset for `string.sub`
  - `byte_len`: byte length (excluding newline)
  - `newline`: boolean, whether line ends with `\n`
  
- **`LabelInfo`**: Internal label representation during rendering
  - `start_char`: 1-based char offset (inclusive)
  - `end_char`: 1-based char offset (inclusive, `nil` for zero-width spans)
  - `multi`: boolean, whether this is a multiline label
  - `label`: reference to original `Label` object (has `message`, `color`, `priority`)
  
- **`Config`**: Plain table with fields:
  - `compact`: boolean (default false) - compact arrow spacing
  - `tab_width`: integer (default 4)
  - `char_set`: "unicode" or "ascii" (default "unicode")
  - `index_type`: "char" or "byte" (default "char")
  - `color`: function or `false` (default false = no color)
  - `label_attach`: "start" or "middle" (default "middle")
  - `multiline_arrows`: boolean (default true)
  - `cross_gap`: boolean (default false)
  - `underlines`: boolean (default true)

Key design decisions (why code is structured this way)

**Source handling**
- Pre-computes both character and byte offsets so the renderer can switch between `char` and `byte` index types at runtime.
- Uses 1-based indexing (Lua convention) vs Rust's 0-based.
- Uses closed intervals `[start, end]` (both inclusive) vs Rust's half-open `[start, end)`.
- Empty spans represented as `(pos, nil)` where `end_char = nil`, equivalent to Rust's `pos..pos`.
- Line lengths exclude newlines (for simplicity), but `line.len + (line.newline and 1 or 0)` recovers Rust's `line.len()`.

**Architectural improvements over Rust original**

1. **Flattened rendering loops** (O(n) vs O(n²))
   - Original Rust: Nested loops `for col in 0..len { for i in 0..col+1 { ... } }`
   - This implementation: Single loop `for info in multi_labels { ... }` with carefully scoped variables
   - **Key insight**: The inner loop only affects output when `i == col` (due to `!is_parent` filters). By making each `info` correspond to one output column, the inner loop becomes redundant.
   - **Variable scoping strategy**:
     - `vbar`, `corner`: Reset per iteration (local variables) - analogous to resetting per `col`
     - `hbar`, `margin_ptr`: Preserved across iterations (outer variables) - analogous to accumulating in inner loop
   - **Equivalence verified**: All tests pass, output is pixel-perfect.

2. **Simplified margin rendering**
   - Eliminated complex pointer comparisons and multi-stage filtering.
   - Removed no-op code (where `hbar` is set then immediately filtered away).
   - Consolidated conditions using early returns and direct logic flow.

3. **No `continue` or `goto`**
   - All control flow uses nested `if-elseif-else` chains.
   - Maintains readability without Lua 5.2+ `goto` or multiple `return` points.

4. **Tab width calculation**
   - Original (0-based): `tab_width - col % tab_width`
   - This implementation (1-based): `tab_width - ((col - 1) % tab_width)`
   - Equivalent forms verified with `tab_width = 4` across `col = 1, 2, 5, 8`.

**Index type conversions**
- Original implementation uses 0-based half-open ranges: `span.start..span.end` means `[start, end)`.
- This implementation uses 1-based closed ranges: `start_char, end_char` means `[start, end]`.
- Conversion rules (from reference implementation):
  - Original `start` → This `start + 1` (shift to 1-based)
  - Original `end` → This `end` (because original's `end` is exclusive, this is inclusive)
  - Empty span: Original `idx..idx` → This `(idx + 1, nil)`
  
**UTF-8 handling**
- Relies on `lua-utf8` library (compatible with Lua 5.1+).
- Only handles `\n` newlines (not Unicode line separators like U+2028).
- Rationale: Simplicity and cross-language consistency (not all languages follow Unicode newline rules).

**Rendering logic**
- Glyph tables (`Characters.unicode` / `Characters.ascii`) provide rendering symbols.
- Color system uses function-based callback for flexibility.
- Writer abstraction (`W:label()`, `W:use_color()`) encapsulates output buffering and color state.

Local conventions and patterns for contributors
- Use ASCII glyphs in tests to keep expectations stable unless a test intentionally exercises the Unicode character set.
- Prefer pure functions and local helpers; avoid capturing globals other than standard Lua libraries (`utf8`, `string`, etc.).
- When adding API surface, expose it via `ariadne.lua` and add matching tests in `test.lua` to lock behaviour.

Developer workflows & commands
- Run tests: `lua test.lua` (ensure `luaunit.lua` is available; `luarocks install luaunit` if using a system copy).
- Collect coverage: `luacov` integration is triggered by requiring `luacov` in `test.lua`; run `lua -lluacov test.lua` for reports.
- Format/check: project sticks to hand-formatted Lua; keep indentation at tabs in `ariadne.lua` to match existing style.

Patterns to watch when editing
- Any change affecting rendering should update corresponding expectations in `test.lua`; the suite contains explicit string comparisons.
- **All tests must verify complete output**: Every test must use `lu.assertEquals(msg, expected_output)` with the full expected string, including all color codes, whitespace, and newlines. Never use partial checks like `assertNotNil(msg:find(...))` or `assertTrue(# msg > 0)`.
- **Trailing whitespace handling**: Use `remove_trailing()` helper function when comparing test output to strip trailing spaces from each line. This prevents fragile whitespace comparisons while preserving semantic correctness.
- **Color code testing**: When testing color output, use `("%q"):format(msg)` to make escape sequences visible in test expectations. Only use color codes in one or two tests to cover color-related code paths; prefer `no_color_ascii()` config for all other tests to keep expectations readable.
- **Multi-source diagnostics**: Use `ariadne.Cache.new()` (not `Source.new("")`) to create a proper cache for multi-source tests with multiple files.
- UTF-8 handling relies on `utf8.len`/`utf8.offset`. Guard code paths when targeting Lua without built-in UTF-8 library.
- Config mutations are shared by reference; call `ariadne.config()` per report when you need isolated settings.

Test development workflow
1. Run tests: `lua test.lua`
2. Collect coverage: `rm -f luacov.* && lua -lluacov test.lua && luacov ariadne.lua > /dev/null`
3. Find uncovered lines: `rg -C 3 '^\*+0 ' luacov.report.out` (shows code with context, not line numbers)
   - The luacov.report.out format: `<hit_count> <code>` where `***0` (variable-length stars) means uncovered
   - Use context to identify which function/section contains uncovered code
   - HTML reports have line numbers but are not terminal-friendly
4. Add targeted tests for uncovered branches
5. Verify with `rm -f luacov.* && lua -lluacov test.lua && luacov ariadne.lua > /dev/null && rg -C 3 '^\*+0 ' luacov.report.out`

Concrete examples to cite
- Basic error: 
  ```lua
  local report = ariadne.Report.build("Error", ariadne.Span.new(1, 5))
      :set_message("can't compare apples with oranges")
      :add_label(ariadne.Label.new(1, 5):with_message("This is an apple"))
      :finish()
  local output = report:write_to_string(ariadne.Source.new("apple == orange"))
  ```
- Multi-label layout: see `TestWrite.test_multiple_labels_same_span` in `test.lua` for overlapping arrow output expectations.
- Color support:
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

What you (AI agent) should do first when changing code
1. Re-run `lua test.lua` to ensure rendering changes match expectations.
2. If diagnostics output intentionally changes, update the literal strings in `test.lua` that assert on the new output.
3. Confirm both ASCII and Unicode glyph sets still behave, especially when toggling `config.char_set` or `config.index_type`.
4. Check coverage: `rm -f luacov.* && lua -lluacov test.lua && luacov ariadne.lua > /dev/null && rg -C 3 '^\*+0 ' luacov.report.out`

**CRITICAL: Always read terminal output**
- **NEVER** run a terminal command without immediately reading its output.
- After calling `run_in_terminal`, the output is NOT automatically shown to you.
- You MUST explicitly check the terminal output using one of these methods:
  1. Check the `<function_results>` block immediately after the tool call
  2. Use `get_terminal_output(id)` if you need to retrieve output later
  3. Use `terminal_last_command()` to see what command ran
- **Common mistake**: Running multiple commands without checking output, then asking "what happened?"
- **Fix**: Read output after EVERY terminal command before proceeding.

**CRITICAL: Update instructions when corrected**
- When the user points out a mistake or recurring error pattern, **immediately** update this instructions file.
- Do NOT wait to be reminded multiple times about the same mistake.
- Add the correction to the relevant section (e.g., "What you (AI agent) should do first", "Patterns to watch", etc.).
- This file is your knowledge base - keep it accurate and up-to-date.

If something is unclear
- Ask which Lua version/environment the change must support (Lua 5.1, LuaJIT, 5.4, etc.).
- Clarify whether performance trade-offs are acceptable before refactoring core loops (e.g. span iteration).

---

## Current development status

### Project maturity
- ✅ **Core implementation complete**: All rendering logic ported and tested
- ✅ **Test coverage**: 100% (all reachable code covered)
- ✅ **Pixel-perfect output**: All test cases produce identical output to reference implementation
- ✅ **Performance optimized**: O(n) rendering vs original O(n²) nested loops

### Active TODO
**Priority 1: Complete test coverage** ✅ **COMPLETE**
- Current: 100% coverage (all reachable code covered, 54 tests passing)
- Dead code removed:
  - Line 67: `Line:span()` - Removed unused helper method
  - Line 1046: `elseif vbar and hbar and not cfg.cross_gap` - Commented out unreachable branch
    - Analysis: `hbar` and `corner` are always set together (`hbar, corner = info, info`), so the `elseif corner` branch always matches first, making this branch unreachable
  - Line 1340: `elseif vbar.info.multi and row == 1 and cfg.compact` - Commented out unreachable branch
    - Analysis: When `vbar` exists at `col ~= ll.col`, either `is_hbar` is true (handled by previous branches) or the default vbar rendering applies. The combination of conditions required for this branch (vbar exists, col != ll.col, is_hbar=false, vbar.info.multi=true, row=1, cfg.compact=true) appears impossible to satisfy in practice.
- All previously uncovered lines now have test coverage:
  - ✅ Line 1204: `return nil` when underlines disabled → `test_underlines_disabled`
  - ✅ Line 1222: `result = ll` shorter label priority → `test_underline_shorter_label_priority`
  - ✅ Test added for `cross_gap = false` behavior → `test_cross_gap_vbar_hbar`

**Priority 2: Line width limiting feature** (See "Next development phase" below)
- Status: Not started
- Ready to begin now that 100% test coverage is achieved

### Known limitations
- Only supports `\n` newlines (not Unicode line separators)
- No streaming output (full diagnostic built in memory)
- Color codes must follow `\27[...m` format (no validation)

---

## Critical implementation details for AI agents

### Loop flattening equivalence (render_margin)

**Context**: This implementation transforms nested O(n²) loops into a single O(n) loop.

**Original structure** (from Rust reference):
```rust
for col in 0..multi_labels_with_message.len() + 1 {
    let mut vbar = None;
    let mut hbar = None;
    let mut corner = None;
    let mut margin_ptr = None;
    
    // Inner loop: iterates 0..col+1
    for (i, label) in multi_labels_with_message[0..(col + 1)].iter().enumerate() {
        let is_parent = i != col;  // Only i == col affects output
        // Update vbar, hbar, corner based on is_parent
    }
    // Output one character using vbar, hbar, corner
}
```

**Flattened structure** (this implementation):
```lua
local hbar, margin_ptr  -- Global: accumulated across iterations
local margin_ptr_is_start

for _, info in ipairs(multi_labels_with_message) do
    local vbar, corner  -- Local: reset per iteration
    
    -- Compute vbar, corner for this info
    -- Update global hbar, margin_ptr if needed
    -- Output one character
end
```

**Equivalence proof**:
1. **Variable scoping matches semantic lifetime**:
   - Original `vbar`/`corner` reset per `col` → Local variables reset per iteration ✓
   - Original `hbar`/`margin_ptr` accumulate in inner loop → Outer variables preserve across iterations ✓

2. **`is_parent` elimination**:
   - Original: Inner loop filters with `!is_parent` (i.e., `i == col`)
   - Effect: Only the last iteration (`i == col`) sets `vbar`/`corner`
   - This implementation: Each iteration corresponds to one `col`, directly sets `vbar`/`corner`
   - **Key insight**: The inner loop is redundant because only `i == col` matters for `vbar`/`corner`

3. **No-op code removal**:
   - Original sets `hbar = margin.label` then immediately filters it if `hbar == margin_label`
   - This implementation omits this dead code path entirely ✓

**Verification**: All tests pass with pixel-perfect output.

### Index conversion cheat sheet

| Concept | Original (0-based, half-open) | This implementation (1-based, closed) |
|---------|-------------------------------|--------------------------------------|
| Single char at pos 0 | `0..1` | `(1, 1)` |
| Empty span at pos 5 | `5..5` | `(6, nil)` |
| Range [10, 20) | `10..20` | `(11, 20)` |
| Line offset | `line.offset()` returns 0-based | `line.offset` is 1-based |
| String slicing | `s[start..end]` | `s:sub(byte_offset, byte_offset + byte_len - 1)` |

**Critical gotcha**: When converting `end_char or start_char - 1`:
- Empty span: `end_char == nil`, so `start_char - 1` represents original's `start..start`
- Non-empty: `end_char` is the last character (inclusive), matching original's `end - 1`

### Tab width calculation (1-based correction)

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
|---------------|----------------------|--------|
| 1 | 0 | 4 |
| 2 | 1 | 3 |
| 5 | 4 | 4 |
| 8 | 7 | 1 |

---

## Next development phase: Line width limiting

### Overview
Add optional `line_width` config to intelligently truncate/split long diagnostic lines while preserving readability.

### Motivation
Current behavior (e.g., `test_label_at_end_of_long_line`) renders 900+ character lines in full, making terminal output unusable. Proposed enhancement:
- Truncate long headers with `...`
- Show local context for labels on long lines
- Split multi-label lines into multiple rows
- Convert oversized single-line labels to multiline format

### Requirements

**REQ-1: Header truncation**
- If `,-[ /very/long/path/to/file.lua:123:45 ]` exceeds `line_width`, truncate path to `.../file.lua:123:45`
- Preserve minimum readability: always show filename + location even if `line_width` is small

**REQ-2: Local context windowing**
- For single-label lines: show only `[start_col - margin, end_col + margin]` range
- Prefix with `...` if start is truncated, suffix if end is truncated
- Example: `1 | ...long code[label]...` instead of full line

**REQ-3: Multi-label splitting**
- If multiple labels + messages exceed `line_width`, render as separate "virtual rows"
- Each virtual row shows same line number but different label subset
- Margin symbols (`vbar`) must connect across virtual rows

**REQ-4: Forced multiline conversion**
- If single label + message still exceeds `line_width` after windowing, convert to multiline label
- Example: `[very long span -------msg]` becomes:
  ```
  ,-> [very long
  |-> span]
      `--- msg
  ```

### Implementation phases

**Phase 0: Infrastructure (1-2 days)**
- Add `Config.line_width` field (default `nil` = no limit)
- Add `Characters.ellipsis`: `"…"` (unicode) / `"..."` (ascii)
- Add `Color` category `"ellipsis"`
- Implement helper functions:
  - `calc_display_width(text, cfg)`: Compute rendered width (accounts for tabs, UTF-8, colors)
  - `truncate_to_width(text, max_width, cfg)`: Safe UTF-8 truncation
- **Validation**: All existing tests pass with `line_width = nil`

**Phase 1: Header truncation (2-3 days)**
- Modify `render_header()` to truncate file path when exceeding `line_width`
- Strategy: Keep filename + location, truncate parent directories
- Edge cases: very long line numbers, very small `line_width`
- **Test**: Add `test_header_truncation` with 40-char limit

**Phase 2: Single-label windowing (3-5 days)**
- Modify `render_line()` to accept `col_start, col_end` range parameters
- Compute optimal window: `[min(label.start) - margin, max(label.end) + margin]`
- Add ellipsis rendering for truncated context
- Update `calc_arrow_len()` to work with windowed ranges
- **Test**: Modify `test_label_at_end_of_long_line` with `line_width = 80`
- **Challenges**:
  - Column alignment: label positions must adjust to window offset
  - Margin symbols: multiline labels may extend outside window

**Phase 3: Multi-label splitting (5-7 days)**
- Implement "virtual row" concept: same source line rendered multiple times
- Split labels into groups that fit within `line_width`
- First group shows line number, subsequent groups show spaces
- Preserve `vbar` continuity across groups
- **Test**: Add `test_multi_label_split` with 3+ overlapping labels
- **Challenges**:
  - Greedy vs optimal splitting (start with greedy)
  - Message alignment across virtual rows
  - Interaction with existing "skipped lines" logic

**Phase 4: Forced multiline (2-3 days)**
- Detect "unsplittable" oversized labels
- Runtime conversion: set `label.multi = true` during rendering
- Adjust `render_margin()` and `render_arrows()` for dynamic multiline labels
- **Test**: Add `test_force_multiline` with 200-char single label
- **Challenges**:
  - Mutating label info during render (violates immutability)
  - Message positioning for converted labels

**Phase 5: Edge cases & polish (3-5 days)**
- Handle extreme widths: `line_width < 20`, `line_width > 1000`
- UTF-8 safety: ensure truncation respects character boundaries
- Color code handling: exclude ANSI escapes from width calculation
- Performance: cache width calculations
- **Test**: Fuzz testing with random labels and widths

### Technical challenges

**Challenge 1: Width prediction consistency**
- Problem: Must predict rendered width before actual rendering
- Solution: Implement dry-run mode in `Writer` that calculates width without output
- Risk: Mismatch between prediction and reality leads to overflow/underflow

**Challenge 2: Virtual row margin symbols**
- Problem: Margin symbols must connect vertically across split rows
- Example:
  ```
  1 | code [A--msgA]
    |      ^
  1 | code [B--msgB]  <- Same line number, different label
  ```
- Solution: Track `vbar` state across virtual rows, similar to current "skipped line" logic

**Challenge 3: UTF-8 truncation safety**
- Problem: Naive `string.sub()` can split multi-byte characters
- Solution: Use `utf8.offset()` to find safe truncation points
- Test: Truncate strings with emoji, combining characters, RTL text

**Challenge 4: Backward compatibility**
- Problem: Must not break existing API or tests
- Solution: All new behavior gated by `line_width ~= nil` check
- Validation: Run full test suite with and without `line_width`

### Success criteria

- [ ] All existing tests pass with `line_width = nil`
- [ ] New tests cover all 4 requirements
- [ ] `test_label_at_end_of_long_line` produces readable 80-char output
- [ ] No UTF-8 corruption in truncated text
- [ ] Performance: < 10% slowdown for typical reports
- [ ] Documentation: API examples and migration guide

### Current status
**Not started** - Awaiting approval to begin Phase 0.

---

## Feedback request
- Let the maintainer know if more setup detail (e.g. LuaRocks manifests, coverage instructions) would help future edits.
