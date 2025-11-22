# GitHub Copilot Instructions

> **Related documents**: 
> - Project Structure: project-structure.md in .github - Technical architecture and design decisions
> - Development Roadmap: roadmap.md in .github - TODO, plans, and completed work

**IMPORTANT for AI agents**: When documenting challenging coverage cases, complex algorithms, or significant architectural decisions, update `project-structure.md` (not this file). This instructions file focuses on workflows and conventions.

This repository is a Lua implementation of the Ariadne diagnostics renderer. Originally ported from the Rust `ariadne` library, it now serves as the primary implementation with architectural improvements for performance and clarity.

## Quick Context

- **Language**: Lua 5.1+ with UTF-8 support (tested against Lua 5.1/LuaJIT)
- **Dependencies**: `lua-utf8`, `luaunit`, optional `luacov`
- **Tests**: Run `lua test.lua` from project root
- **Coverage**: 100% (all reachable code covered, 55 tests passing in stable state)
- **Key files**: 
  - `ariadne.lua` - All runtime code (~1500 lines)
  - `test.lua` - Exhaustive regression suite (~1400 lines)

**Current development state**: Check `roadmap.md` for active feature work. During feature development, tests may temporarily fail - this is expected. Always check roadmap to understand which tests are work-in-progress vs. regressions.

For detailed architecture, see project-structure.md.

For development status and plans, see roadmap.md.

---

## Collaboration Workflow (for AI agents)

When implementing new features (like line width limiting):

### Test-Driven Development
1. **Agent writes test cases first** (following existing test patterns in `test.lua`)
2. **User reviews and approves** test cases for correctness and completeness
3. **Tests define expected behavior** before any implementation

### Implementation Guidance

⚠️ **CRITICAL: Think Before Providing Solutions**

**MANDATORY workflow before providing ANY implementation suggestion**:
1. **Think deeply** about the requirement (understand what user really needs)
2. **Think again** about potential issues (edge cases, performance, correctness)
3. **Think third time** about the approach (is this the best solution?)
4. **Only then** provide the suggestion (pseudo-code or algorithmic approach)

**User's explicit requirement**: "Don't rush to write code. Think more. Think at least three times and make sure there are no issues with the approach before providing it. Only write code when I explicitly request it."

- **Never write code immediately** - always think first
- **Never provide code unless explicitly requested** - give approach/algorithm instead
- **Self-check rigorously** - verify your thinking before presenting
- **Ask questions** when uncertain - don't guess or assume

**When providing implementation suggestions**:
1. Identify which functions need modification
2. Provide pseudo-code or algorithmic approach (NOT full implementation)
3. Highlight key technical points (UTF-8 handling, edge cases, etc.)
4. Point out open questions that need user confirmation

**After agent provides suggestions**:
1. User evaluates feasibility and makes final architectural decisions
2. User writes actual code implementation
3. Agent assists with debugging and analysis when problems arise

### Iterative Development
- Start with simple cases, add complexity gradually
- Run tests frequently: `lua test.lua` after each change
- Agent helps identify edge cases and potential issues
- Both parties discuss trade-offs and design decisions

### Code Ownership
- **User maintains full control** over code quality and architecture
- **Agent acts as pair programmer**: review, suggest, assist (not implement)
- **User makes all final decisions** on implementation details
- Agent never writes production code without explicit user request

---

## Agent Guidelines

### Local Conventions and Patterns

- Use ASCII glyphs in tests to keep expectations stable unless intentionally testing Unicode
- Prefer pure functions and local helpers; avoid capturing globals other than standard Lua libraries
- When adding API surface, expose it via `ariadne.lua` and add matching tests in `test.lua`

### Test Development Workflow

1. Run tests: `lua test.lua`
2. Collect coverage: `rm -f luacov.* && lua -lluacov test.lua && luacov ariadne.lua > /dev/null`
3. Find uncovered lines: `rg -C 3 '^\*+0 ' luacov.report.out`
   - The luacov.report.out format: `<hit_count> <code>` where `***0` (variable-length stars) means uncovered
   - Use context to identify which function/section contains uncovered code
4. Add targeted tests for uncovered branches
5. Verify coverage again

### Test Writing Patterns

- **All tests must verify complete output**: Every test must use `lu.assertEquals(msg, expected_output)` with the full expected string, including all color codes, whitespace, and newlines. Never use partial checks like `assertNotNil(msg:find(...))` or `assertTrue(# msg > 0)`.
- **Trailing whitespace handling**: Use `remove_trailing()` helper function when comparing test output to strip trailing spaces from each line. This prevents fragile whitespace comparisons while preserving semantic correctness.
- **Color code testing**: When testing color output, use `("%q"):format(msg)` to make escape sequences visible in test expectations. Only use color codes in one or two tests to cover color-related code paths; prefer `no_color_ascii()` config for all other tests to keep expectations readable.
- **Multi-source diagnostics**: Use `ariadne.Cache.new()` (not `Source.new("")`) to create a proper cache for multi-source tests with multiple files.
- **Generate realistic test data**: Use string repetition like `("dir/"):rep(20)` for long paths, `("line\n"):rep(200)` for many lines. Never hardcode short values when testing overflow/truncation behavior.
- **Always add labels when testing reference headers**: Reference headers only display when at least one label is present. Use `:add_label(ariadne.Label.new(...):with_message("..."))` in all tests that expect header output.
- **Calculate display widths accurately**: CJK characters are width 2, ASCII is width 1, tabs expand to `tab_width` spaces. Verify calculations manually before writing expected outputs.

### Quality Standards

⚠️ **CRITICAL: Self-Check Before Presenting Work**

Before showing test cases or code to the user, you MUST:

1. **Verify test data is realistic**: 
   - Long paths should actually be long (use string repetition)
   - Multi-line tests should have many lines (use string repetition)
   - Don't hardcode values like "/very/long/path" (only 16 chars - not long!)

2. **Verify all required elements are present**:
   - Tests expecting headers must have labels (otherwise header won't display)
   - Tests expecting arrows must have non-empty spans
   - Tests expecting messages must set message text

3. **Verify calculations are correct**:
   - Calculate actual display widths for UTF-8 strings
   - Account for tab expansion in width calculations
   - Check that truncation/overflow will actually occur with your test data

4. **Think through the logic**:
   - Will this test actually exercise the code path I'm targeting?
   - Does the expected output match what the implementation should produce?
   - Are there edge cases I'm missing?

**User's expectation**: "我不要求你一次写对，但是我不能容忍你完全不思考"
- Errors are acceptable, but thoughtless work is not
- Self-check your work before presenting it
- Don't waste user's time with obviously flawed test cases

### Developer Workflows & Commands

- **Run tests**: `lua test.lua`
- **Collect coverage**: `lua -lluacov test.lua && luacov ariadne.lua`
- **Format**: Project uses hand-formatted Lua; keep indentation at tabs in `ariadne.lua`

### What to Do First When Changing Code

1. Re-run `lua test.lua` to ensure rendering changes match expectations
2. If diagnostics output intentionally changes, update the literal strings in `test.lua` that assert on the new output
3. Confirm both ASCII and Unicode glyph sets still behave, especially when toggling `config.char_set` or `config.index_type`
4. Check coverage: `rm -f luacov.* && lua -lluacov test.lua && luacov ariadne.lua > /dev/null && rg -C 3 '^\*+0 ' luacov.report.out`

---

## CRITICAL Requirements for AI Agents

### ⚠️ ABSOLUTE REQUIREMENT: Always Read Terminal Output

- **NO EXCEPTIONS**: You MUST read the output of EVERY terminal command you execute.
- **ENFORCEMENT**: If you run a terminal command, the VERY NEXT action must be examining its output.

**CRITICAL: How to get terminal output**:
- `run_in_terminal` with `isBackground=false`: Output may NOT appear in `<function_results>` (often shows only prompt)
- **YOU MUST use `terminal_last_command` tool immediately after ANY terminal command**
- `terminal_last_command` returns: command, directory, exit code, and **complete output**
- For background processes: use `get_terminal_output` with terminal ID

**Correct workflow**:
```
1. Call run_in_terminal(command, isBackground=false)
2. IMMEDIATELY call terminal_last_command  ← MANDATORY!
3. Read the output from terminal_last_command results
4. Describe what you see in the output
5. Only then proceed to next action
```

**Common mistake**: Assuming `<function_results>` from `run_in_terminal` contains the output.

**Example of WRONG behavior**:
```
<run_in_terminal: lua test.lua>
<see only "$ [00:28:08]" in function_results>
<assume no output or success>  ← WRONG! You didn't check terminal_last_command!
```

**Example of CORRECT behavior**:
```
<run_in_terminal: lua test.lua>
<see only "$ [00:28:08]" in function_results>
<immediately call terminal_last_command>
<observe: "terminal_last_command shows exit code 1 and error message: ...">
<take appropriate action based on the actual output>
```

**Violation consequences**: If you don't use `terminal_last_command`, you will miss critical output and waste time debugging blind.

### ⚠️ CRITICAL: Update Instructions When Corrected

- When the user points out a mistake or recurring error pattern, **immediately** update this instructions file.
- Do NOT wait to be reminded multiple times about the same mistake.
- Add the correction to the relevant section (e.g., "What to Do First", "Test Writing Patterns", etc.).
- This file is your knowledge base - keep it accurate and up-to-date.

### ⚠️ CRITICAL: Auto-Generate Git Commit Messages After Documentation Updates

**Workflow**: When user requests documentation updates (project-structure.md, roadmap.md, or this file):

1. **Complete all documentation edits first**
2. **Automatically generate a git commit message** (don't wait for explicit request)
3. **Format**: Follow Conventional Commits style

**Commit message template**:
```
<type>(<scope>): <subject>

<body>

<footer>
```

**Guidelines**:
- **Type**: Use `docs` for documentation-only changes, `fix` for bug fixes with documentation
- **Scope**: Specify the component (e.g., `multiline`, `windowing`, `clustering`)
- **Subject**: Concise summary (≤50 chars), imperative mood ("Fix X" not "Fixed X")
- **Body**: 
  - Detail each change with context
  - Include line numbers for code fixes
  - Explain rationale for design decisions
  - Keep lines ≤72 chars (wrap manually)
- **Footer**: Reference related issues/PRs, test cases, or documentation sections

**Example** (for bug fixes with doc updates):
```
fix(windowing): fix 3 bugs in multiline label rendering with width limits

1. Line 727: Only extend margin labels to line end when no width limit
   - Prevents margin labels from extending beyond window in virtual rows
   
2. Line 736: Convert start_char to column for min_col calculation
   - For multiline: use ll.col (already relative)
   - For inline: convert via line_col(line, start_char)
   
3. Line 985: Add margin label check to ellipsis padding condition
   - Margin end labels need hbar fill for visual continuity
   - Original condition only checked draw_msg flag

Test: TestLineWindowing.test_multiline
Docs: project-structure.md "Bug Fixes (2025-11-23)"
```

**When to generate**:
- User explicitly requests: "update docs and generate commit message"
- User requests doc updates without mentioning commit message (auto-generate anyway)
- After completing multi-file documentation updates

**When NOT to generate**:
- User only asks questions (no edits made)
- User is still iterating on changes (wait for final state)
- User explicitly says "don't generate commit message yet"

---

---

## Questions to Ask When Unclear

- Which Lua version/environment the change must support (Lua 5.1, LuaJIT, 5.4, etc.)?
- Are performance trade-offs acceptable before refactoring core loops (e.g. span iteration)?
- Should we update project-structure.md or roadmap.md for this change?

