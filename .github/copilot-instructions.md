# GitHub Copilot Instructions

> **Related documents**: 
> - [Project Structure](project-structure.md) - Technical architecture and design decisions
> - [Development Roadmap](roadmap.md) - TODO, plans, and completed work

**IMPORTANT for AI agents**: When documenting challenging coverage cases, complex algorithms, or significant architectural decisions, update `project-structure.md` (not this file). This instructions file focuses on workflows and conventions.

This repository is a Lua implementation of the Ariadne diagnostics renderer. Originally ported from the Rust `ariadne` library, it now serves as the primary implementation with architectural improvements for performance and clarity.

## Quick Context

- **Language**: Lua 5.1+ with UTF-8 support (tested against Lua 5.1/LuaJIT)
- **Dependencies**: `lua-utf8`, `luaunit`, optional `luacov`
- **Tests**: Run `lua test.lua` from project root
- **Coverage**: 100% (all reachable code covered, 55 tests passing)
- **Key files**: 
  - `ariadne.lua` - All runtime code (~1500 lines)
  - `test.lua` - Exhaustive regression suite (~1400 lines)

For detailed architecture, see [project-structure.md](project-structure.md).

For development status and plans, see [roadmap.md](roadmap.md).

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

---

## Questions to Ask When Unclear

- Which Lua version/environment the change must support (Lua 5.1, LuaJIT, 5.4, etc.)?
- Are performance trade-offs acceptable before refactoring core loops (e.g. span iteration)?
- Should we update project-structure.md or roadmap.md for this change?

