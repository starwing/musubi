# Development Roadmap

This document tracks the project's development status, active TODOs, completed work, and planned features.

## Current Status

### Project Maturity
- ✅ **Core implementation complete**: All rendering logic ported and tested
- ✅ **Test coverage**: 100% (all reachable code covered, 77 tests passing)
- ✅ **Pixel-perfect output**: All test cases produce identical output to reference implementation
- ✅ **Performance optimized**: O(n) rendering vs original O(n²) nested loops
- ✅ **Line width limiting**: Phase 0-2a complete (header truncation + line windowing)
- ✅ **Unicode support**: Full CJK and mixed character width handling

### Known Limitations
- Only supports `\n` newlines (not Unicode line separators)
- No streaming output (full diagnostic built in memory)
- Color codes must follow `\27[...m` format (no validation)

## Active TODO

**Priority 1: Line width limiting feature - Phase 2b+** (See "Planned Features" section below)
- Status: Phase 2a complete, Phase 2b not started
- Current state: Single-label windowing works, multi-label splitting pending
- Next phase: POC for virtual rows concept

## Completed Work

### ✅ 100% Test Coverage Achievement (2025-11-10)

**Final status**: 100% coverage (all reachable code covered, 55 tests passing)

**Dead code identified and removed**:
- Line 67: `Line:span()` - Removed unused helper method
- Line 1046: `elseif vbar and hbar and not cfg.cross_gap` - Commented out unreachable branch
  - Analysis: `hbar` and `corner` are always set together (`hbar, corner = info, info`), so the `elseif corner` branch always matches first, making this branch unreachable

**All edge cases now have test coverage**:
- ✅ Line 1204: `return nil` when underlines disabled → `test_underlines_disabled`
- ✅ Line 1222: `result = ll` shorter label priority → `test_underline_shorter_label_priority`
- ✅ Line 1341: `a = draw.uarrow` compact multiline vbar → `test_uarrow` (see project-structure.md for details)
- ✅ Cross-gap behavior: `test_cross_gap_vbar_hbar`

## Planned Features

### Line Width Limiting

**Overview**: Add optional `line_width` config to intelligently truncate/split long diagnostic lines while preserving readability.

**Motivation**: Current behavior (e.g., `test_label_at_end_of_long_line`) renders 900+ character lines in full, making terminal output unusable.

**Proposed enhancements**:
- Truncate long headers with `...`
- Show local context for labels on long lines
- Split multi-label lines into multiple rows
- Convert oversized single-label labels to multiline format

**Core principle: "Minimum meaningful width"**
- `line_width` is a **soft limit**: prioritize displaying core information over strict width compliance
- If displaying essential information (label position + message) requires exceeding `line_width`, do so
- Rationale: Users may resize terminal after seeing output; avoid forcing recompilation
- Simplification: No need to handle message truncation or wrapping (messages always display fully)

### Requirements

**REQ-1: Header truncation**
- If `,-[ /very/long/path/to/file.lua:123:45 ]` exceeds `line_width`, truncate path to `.../file.lua:123:45`
- Available width = `line_width - line_no_width - 5` (for margin symbols and brackets)
- Preserve filename + location; truncate parent directories from start
- Tab characters in `source.id` normalized to spaces before calculation

**REQ-2: Local context windowing**
- For single-label lines: show only local context around label if line is too long
- Strategy: Truncate code before label (keep suffix), show `...` prefix
- Example: `1 | ...long code[label]...` instead of full line
- Priority: Ensure label and message are always visible (ignore `line_width` if necessary)

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

### Implementation Phases

**Phase 0: Infrastructure** ✅ *Completed 2025-11-14*
- ✅ `Config.line_width` field added (default `nil` = no limit)
- ✅ `Characters.ellipsis` already existed: `"…"` (unicode) / `"..."` (ascii)
- ✅ luautf8 0.2.0 provides `utf8.width()`, `utf8.widthindex()`, `utf8.widthlimit()`
- ✅ All existing tests pass with `line_width = nil`

**Phase 1: Header truncation** ✅ *Completed 2025-11-14*
- ✅ Added `MIN_FILENAME_WIDTH` constant (8 chars minimum for meaningful info)
- ✅ Extracted `calc_location()` helper to compute `"line:col"` strings
- ✅ Modified `render_reference()` to truncate `source.id` when exceeding `line_width`
- ✅ Tab normalization: `\t` → single space (not tab_width expansion)
- ✅ Soft limit implementation: enforce MIN_FILENAME_WIDTH even if exceeds line_width
- ✅ Width calculation formula:
  ```
  fixed_width = line_no_width + 9 + utf8.width(loc)
  avail = line_width - fixed_width - utf8.width(ellipsis)
  truncated_id = ellipsis .. id:sub(utf8.widthlimit(id, -avail))
  ```
- ✅ **Tests added** (9 new tests, all passing):
  - `test_header_truncation_long_path` - Basic long path truncation
  - `test_header_truncation_large_line_number` - Dynamic line_no_width
  - `test_header_truncation_utf8_path` - CJK characters (width 2)
  - `test_header_truncation_tab_in_path` - Tab normalization
  - `test_header_truncation_very_narrow` - Extreme narrow width
  - `test_header_no_truncation_when_nil` - No truncation when disabled
  - `test_header_truncation_exact_boundary` - Exact fit
  - `test_header_truncation_one_over_boundary` - Just over limit
  - Coverage: ASCII, UTF-8, tabs, edge cases, soft limits

**Phase 2a: Line windowing (local context around labels)** ✅ *Complete*
- **Implemented**: Intelligent line truncation with left/right ellipsis
- **Strategy**: Center label+message within `line_width`, balance left/right context
- **Core algorithm**:
  - Calculate `arrow_limit = arrow_width + 1 + max_label_width`
  - If fits: show full line
  - If `min_width` overflows: show from `min_col` with right truncation
  - Otherwise: balance left/right context, prioritize right side if insufficient
- **Key functions**:
  - `calc_col_range()`: Returns `start_col, end_col` for windowing
  - Modified `render_line()` and `render_arrows()` to accept `start_col, end_col`
- **Tests added** (11 new tests, all passing):
  - `test_single_label_at_end_of_long_line` - Label at line end (906 chars), centered
  - `test_single_label_in_middle_of_long_line` - Label in middle (805 chars), centered
  - `test_single_label_at_start_of_long_line` - Label at start, only right ellipsis
  - `test_no_windowing_when_line_fits` - Short line, no truncation
  - `test_no_windowing_when_line_width_nil` - Disabled, full display
  - `test_fit_line_width` - Label in middle, fits with right truncation
  - `test_minimum_line_width` - Extreme narrow width (10), message overflow
  - `test_small_msg` - Very short message (1 char)
  - `test_multiple_labels_on_long_line` - Multiple labels, window based on leftmost
  - `test_cjk_characters_in_line` - CJK characters (width 2), proper width calculation
  - `test_mixed_ascii_cjk_characters` - Mixed ASCII/CJK, correct display width
- **Total tests**: 77 (66 baseline + 11 Phase 2a), 100% coverage maintained

### Phase 2a Implementation Summary (Completed)

**Design Decision**: Label+message centering with balanced context

**Final Algorithm**:
```
1. Calculate fixed_width = line_no_width + 4 + margin_width
   - +4: line_no margin (2) + separator (1) + space after arrows (1)
2. Calculate arrow_limit = arrow_width + 1 + max_label_width
   - arrow_width: display width from line start to arrow_len
   - +1: space before message
3. Early exits:
   - No line_width or entire line fits → start_col = 1, end_col = nil
   - min_width overflows → start_col = min_col, end_col with minimal right context
4. Windowing logic:
   - min_skip = arrow_limit - line_width + ellipsis_width + 1
   - If min_skip <= 0: only right truncation needed
   - Otherwise: calculate balance_skip for centering
     - avail_width = total_width - arrow_limit (right context available)
     - right_width = (line_width - min_width) // 2 (ideal right allocation)
     - balance_skip = right_width + max(0, right_width - avail_width)
       (compensate if right side insufficient)
   - start_col = widthindex(min_skip + balance_skip)
   - end_col = arrow_len + widthindex(1 + max_label_width + balance_skip - ellipsis)
```

**Key Technical Insights**:
- `widthindex(s, width, i)` returns char index relative to position `i` (1-based)
- Negative width parameter: returns 1 (first character satisfies)
- `balance_skip`: extra left skip for centering, compensates for insufficient right context
- `end_col` calculation: ensures message connector stays within display range

**Function Signatures**:
```lua
calc_col_range(line, arrow_len, min_col, max_label_width, line_no_width, 
               ellipsis_width, multi_labels_with_message, src, cfg)
  → start_col, end_col?

render_line(W, line, start_col, end_col, margin_label, line_labels, 
            multi_labels, src, cfg)

render_arrows(W, line_no_width, line, is_ellipsis, arrow_len, start_col, 
              end_col, ellipsis_width, line_labels, margin_label, 
              multi_labels_with_message, src, cfg)
```

**Challenges Resolved**:
- ❌ Initially tried `widthlimit` (returns byte position, wrong tool)
- ✅ Switched to `widthindex` (returns char index, correct)
- ❌ First attempt: skip_width / 2 (didn't account for insufficient right context)
- ✅ Final: balance_skip with compensation logic
- ❌ Confusion about "centering" target (label vs label+message)
- ✅ Clarified: center label+message as visual unit, right side guarantees message space

**Phase 2b: POC for virtual rows (3-5 days)** ⏸️ *Not started*
- Create experimental branch to test virtual row concept
- Implement multi-label splitting in isolation
- Test margin symbol continuity across virtual rows
- Evaluate architectural fit and complexity
- **Decision point**: Proceed with Phase 3 or adjust approach

**Phase 3: Multi-label splitting (5-7 days)** ⏸️ *Pending Phase 2b results*
- Implement "virtual row" concept: same source line rendered multiple times
- Split labels into groups that fit within `line_width`
- Preserve `vbar` continuity across groups
- **Test**: Add `test_multi_label_split` with 3+ overlapping labels
- **Challenges**:
  - Greedy vs optimal splitting (start with greedy)
  - Message alignment across virtual rows
  - Interaction with existing "skipped lines" logic

**Phase 4: Forced multiline (2-3 days)** ⏸️ *Optional - evaluate after Phase 3*
- Detect "unsplittable" oversized labels
- Runtime conversion: set `label.multi = true` during rendering
- **Test**: Add `test_force_multiline` with 200-char single label
- **Note**: May not be needed if Phase 3 provides sufficient solutions

**Phase 5: Edge cases & polish (2-3 days)**
- Handle extreme widths: `line_width < 40`, very large widths
- UTF-8 safety: verify truncation respects character boundaries (handled by luautf8)
- Color code handling: ensure ANSI escapes are stripped before width calculation
- **Test**: Edge cases with combining characters, emoji, zero-width characters

### Technical Challenges

**Challenge 1: UTF-8 width calculation and truncation** ✅ *Solved via luautf8*
- Solution: Use `utf8.widthlimit(s, i, j, [limit], [ambiwidth], [fallback])` for all width operations
- Unified API design:
  - With `limit` parameter: Find truncation position
    - Positive `limit`: truncate from front, return end position
    - Negative `limit`: truncate from back, return start position
  - Without `limit` parameter: Calculate display width of byte range `[i, j]`
  - `ambiwidth`: Integer (1 or 2) for handling ambiguous-width characters
  - Returns: `(pos, width)` where `pos` is `j` when measuring, or truncation point when limiting
- Handles: Double-width characters, combining characters, zero-width modifiers
- Does NOT handle: Tab expansion (application layer responsibility), ANSI color codes (application layer responsibility)
- Newlines: Treated as width-1 characters (no special handling at luautf8 level)

**Challenge 2: line_width as soft limit**
- Problem: Strict width enforcement may truncate essential information
- Solution: "Minimum meaningful width" principle
  - Always display: line numbers, margin symbols, label arrows, full messages
  - Apply truncation only to: reference headers, code context
  - If minimum meaningful display exceeds `line_width`, ignore the limit
- Example: 100-char message on narrow terminal → display fully, ignore `line_width`
- Benefit: Avoids complex message wrapping/truncation logic, maintains information integrity

**Challenge 3: Virtual row margin symbols**
- Problem: Margin symbols must connect vertically across split rows
- Example:
  ```
  1 | code [A--msgA]
    |      ^
  1 | code [B--msgB]  <- Same line number, different label
  ```
- Solution: Track `vbar` state across virtual rows, similar to current "skipped line" logic
- Status: To be explored in Phase 2b POC

**Challenge 4: Backward compatibility**
- Solution: All new behavior gated by `line_width ~= nil` check
- Validation: Run full test suite with and without `line_width`
- No changes to existing tests unless explicitly testing new feature

### Success Criteria

- [ ] All existing tests pass with `line_width = nil`
- [ ] New tests cover all 4 requirements
- [ ] `test_label_at_end_of_long_line` produces readable 80-char output
- [ ] No UTF-8 corruption in truncated text (guaranteed by luautf8)
- [ ] Algorithm complexity: No worse than O(n) for rendering
- [ ] Documentation: API examples and migration guide

### Current Status
**Phase 0 in progress** - Adding infrastructure (Config, Characters, helper functions).

---

## Feedback Requests
- Let the maintainer know if more setup detail (e.g. LuaRocks manifests, coverage instructions) would help future edits.
