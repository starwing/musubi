# Development Roadmap

This document tracks the project's development status, active TODOs, completed work, and planned features.

## Current Status

### Project Maturity
- ✅ **Core implementation complete**: All rendering logic ported and tested
- ✅ **Test coverage**: 100% (all reachable code covered, 55 tests passing)
- ✅ **Pixel-perfect output**: All test cases produce identical output to reference implementation
- ✅ **Performance optimized**: O(n) rendering vs original O(n²) nested loops

### Known Limitations
- Only supports `\n` newlines (not Unicode line separators)
- No streaming output (full diagnostic built in memory)
- Color codes must follow `\27[...m` format (no validation)

## Active TODO

**Priority 1: Line width limiting feature** (See "Planned Features" section below)
- Status: Not started, ready to begin
- Goal: Add optional `line_width` config for intelligent truncation of long diagnostic lines

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

### Implementation Phases

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

### Technical Challenges

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

### Success Criteria

- [ ] All existing tests pass with `line_width = nil`
- [ ] New tests cover all 4 requirements
- [ ] `test_label_at_end_of_long_line` produces readable 80-char output
- [ ] No UTF-8 corruption in truncated text
- [ ] Performance: < 10% slowdown for typical reports
- [ ] Documentation: API examples and migration guide

### Current Status
**Not started** - Awaiting approval to begin Phase 0.

---

## Feedback Requests
- Let the maintainer know if more setup detail (e.g. LuaRocks manifests, coverage instructions) would help future edits.
