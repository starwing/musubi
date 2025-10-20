This repository is a Lua port of the Ariadne diagnostics renderer. It mirrors the Rust library's behaviour while staying idiomatic to Lua 5.1+.

Quick context
- Language: Lua with UTF-8 support (tested against Lua 5.1/LuaJIT).
- Dependencies: `luaunit` for tests, optional `luacov` when gathering coverage.
- Entry points: `ariadne.lua` exports the public API (`config`, `source`, `span`, `label`, `report`, helpers like `error`/`warning`).
- Tests: run `lua test.lua` from the project root once `luaunit` (and `luacov` if desired) are on `package.path`.

High-level architecture (what to know fast)
- `ariadne.lua` contains all runtime code, structured into sections for config, source parsing, labels, rendering, and public helpers.
- `test.lua` is the exhaustive regression suite. It snapshots rendered diagnostics and exercises edge cases (multi-byte chars, zero-width spans, compact mode, etc.).
- `serpent.lua` and `luaunit.lua` are vendored dependencies used by the tests; they should generally remain untouched unless upgrading vendored versions.

Key design decisions (why code is structured this way)
- Source handling pre-computes both character and byte offsets so the renderer can switch between `char` and `byte` index types at runtime.
- Rendering logic aims to stay diffable with the Rust formatter. Helpers like `compute_source_groups`, `render_report`, and glyph tables (`ariadne.unicode`/`ariadne.ascii`) are direct analogues of the original implementation.
- Config objects are plain tables seeded via `ariadne.config`; downstream code expects immutable default fields (e.g. `label_attach`, `tab_width`). Copy before mutating shared configs.

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
- UTF-8 handling relies on `utf8.len`/`utf8.offset`. Guard code paths when targeting Lua without built-in UTF-8 library.
- Config mutations are shared by reference; call `ariadne.config()` per report when you need isolated settings.

Integration points & dependencies
- External consumers require only `ariadne.lua`. Tests pull in `luaunit` and `luacov` (optional) via `require`.
- Glyph tables (`ariadne.unicode`/`ariadne.ascii`) can be overridden by consumers; maintain both when adjusting rendering symbols.

Concrete examples to cite
- Basic error: `ariadne.error(ariadne.span(1, 5)):message("msg"):finish():write_to_string(ariadne.source("text"))`.
- Multi-label layout: see `TestWrite.test_multiple_labels_same_span` in `test.lua` for overlapping arrow output expectations.

What you (AI agent) should do first when changing code
1. Re-run `lua test.lua` to ensure rendering changes match expectations.
2. If diagnostics output intentionally changes, update the literal strings in `test.lua` that assert on the new output.
3. Confirm both ASCII and Unicode glyph sets still behave, especially when toggling `config.char_set` or `config.index_type`.
4. Run `rm -f luacov.*; lua test.lua && luacov ariadne.lua` to ensure coverage remains acceptable.

If something is unclear
- Ask which Lua version/environment the change must support (Lua 5.1, LuaJIT, 5.4, etc.).
- Clarify whether performance trade-offs are acceptable before refactoring core loops (e.g. span iteration).

Feedback request
- Let the maintainer know if more setup detail (e.g. LuaRocks manifests, coverage instructions) would help future edits.
