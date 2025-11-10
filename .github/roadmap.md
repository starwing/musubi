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
- Status: Phase 0 in progress
- Goal: Add optional `line_width` config for intelligent truncation of long diagnostic lines
- Current phase: Infrastructure setup (Config, Characters, helper functions)

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

**Phase 0: Infrastructure (1-2 days)** 🔄 *In Progress*
- Add `Config.line_width` field (default `nil` = no limit)
- Add `Characters.ellipsis`: `"…"` (unicode) / `"..."` (ascii)
- Implement helper functions (depending on luautf8 enhancements):
  - `calc_display_width(text, cfg)`: Wrapper around `utf8.subwidth()` with ANSI color stripping
  - `truncate_to_width(text, max_width, cfg)`: Wrapper around `utf8.truncate_width()` with ellipsis
- **Validation**: All existing tests pass with `line_width = nil`
- **Dependencies**: Requires luautf8 to add:
  - `utf8.subwidth(str, start_byte, end_byte, [tab_width], [start_col])` - compute display width of substring
  - `utf8.truncate_width(str, max_width, [tab_width], [start_col])` - find safe truncation point

**Phase 1: Header truncation (1-2 days)**
- Modify `render_header()` to truncate file path when exceeding `line_width`
- Strategy: Keep filename + location, truncate parent directories with ellipsis
- Edge cases: very long line numbers, very small `line_width`
- **Test**: Add `test_header_truncation` with various widths
- **Goal**: Quick win - visible improvement with minimal risk

**Phase 2a: End-of-line single-label windowing (Simplified, 2-3 days)**
- **Scope**: Only handle labels at/near end of long lines (like `test_label_at_end_of_long_line`)
- Strategy: Show `...` prefix + local context around label
- No changes to multi-label logic or arrow rendering
- **Test**: Modify `test_label_at_end_of_long_line` with `line_width = 80`
- **Goal**: Solve 80% of real-world long-line issues with minimal complexity

**Phase 2b: POC for virtual rows (3-5 days)**
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
- Solution: Use `utf8.subwidth()` and `utf8.truncate_width()` from luautf8
- Handles: Double-width characters, combining characters, zero-width modifiers, tab expansion
- Our responsibility: Strip ANSI color codes before calling luautf8 functions

**Challenge 2: Virtual row margin symbols**
- Problem: Margin symbols must connect vertically across split rows
- Example:
  ```
  1 | code [A--msgA]
    |      ^
  1 | code [B--msgB]  <- Same line number, different label
  ```
- Solution: Track `vbar` state across virtual rows, similar to current "skipped line" logic
- Status: To be explored in Phase 2b POC

**Challenge 3: Architecture compatibility**
- Problem: Current renderer is single-pass; line_width may require two-pass rendering
- Proposed solutions:
  1. **Buffered rendering** (preferred): Render to temp buffer, measure, then output
  2. **Lazy application**: Only apply line_width when needed
  3. **Separate code path**: Dedicated renderer for `line_width ~= nil`
- Decision: Start with buffered approach, switch to #3 if memory issues arise

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
