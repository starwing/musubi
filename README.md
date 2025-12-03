<div align="center">

<h1>Musubi</h1>

**A beautiful diagnostics renderer for compiler errors and warnings**

![Language](https://img.shields.io/badge/language-Lua%20%7C%20C%20%7C%20Rust-blue)
[![Crates.io](https://img.shields.io/crates/v/musubi-rs)](https://crates.io/crates/musubi-rs)
[![docs.rs](https://img.shields.io/docsrs/musubi-rs)](https://docs.rs/musubi-rs)
![Version](https://img.shields.io/badge/version-0.1.0-green)
[![License](https://img.shields.io/badge/license-MIT-orange)](LICENSE)
[![Coverage](https://coveralls.io/repos/github/starwing/musubi/badge.svg?branch=master)](https://coveralls.io/github/starwing/musubi?branch=master)

[Key Features](#key-features) • [Installation](#installation) • [Quick Start](#quick-start) • [API Reference](#api-reference) • [Testing](#testing)

</div>

---

> **📦 For Rust Users**: This README covers the complete Musubi project (Lua/C/Rust implementations).  
> **Looking for Rust API documentation?** → See the comprehensive [Rust API docs](https://docs.rs/musubi-rs) with examples and usage guides.  
> **Rust crate**: [`musubi-rs`](https://crates.io/crates/musubi-rs)

---

## Overview

**Musubi** (結び, "connection" in Japanese) is a high-performance diagnostics renderer inspired by Rust's [Ariadne](https://github.com/zesterer/ariadne) library. It produces beautiful, color-coded diagnostic messages with precise source location highlighting, multi-line spans, and intelligent label clustering.

Originally ported from Rust to Lua for rapid prototyping, Musubi has evolved into a production-ready **multi-language** implementation:
- **Pure Lua**: Feature-complete reference implementation with 100% test coverage
- **C Library**: High-performance port with Lua bindings (`musubi.h`, `musubi.c`)
- **Rust Crate**: Safe FFI wrapper with ergonomic builder API

All implementations produce **pixel-perfect identical output** and share the same test suite (95 tests, 2400+ lines).

### Key Features

✨ **Beautiful Output**
- Multi-line diagnostics with color-coded labels
- Intelligent label clustering and virtual row rendering
- Unicode and CJK character support
- ASCII/Unicode glyph sets for terminal compatibility

🚀 **Performance Optimized**
- O(n) rendering complexity (vs original O(n²))
- Pre-computed width caching for UTF-8 strings
- Binary search for line windowing calculations
- Zero-copy source file handling with streaming support

🎯 **Improved Implementation**
- Cleaner Implement with seprated small functions
- Bugfixes towards original Ariadne implement
- New feature: Line limited support
- New feature: No message label rendered

🛡️ **Production Ready**
- 100% test coverage (all reachable code covered)
- Memory-safe C implementation
- Comprehensive error handling
- Tested on Lua 5.1, 5.4, and LuaJIT

---

## Example

```lua
local mu = require "musubi"
local cg = mu.colorgen()

print(
    mu.report(12)
    :code "3"
    :title("Error", "Incompatible types")
    :label(33, 33):message("This is of type Nat"):color(cg:next())
    :label(43, 45):message("This is of type Str"):color(cg:next())
    :label(12, 48):message("This values are outputs of this match expression"):color(cg:next())
    :label(1, 48):message("The definition has a problem"):color(cg:next())
    :label(51, 76):message("Usage of definition here"):color(cg:next())
    :note "Outputs of match expressions must coerce to the same type"
    :source([[
def five = match () in {
	() => 5,
	() => "5",
}

def six =
    five
    + 1
]], "sample.tao")
    :render())
```

**Output:**

![demo](misc/demo.svg)

---

## Installation

### Requirements

**Lua Implementation:**
- Lua 5.1+ or LuaJIT
- [`lua-utf8`](https://github.com/starwing/luautf8) library (requires `utf8.widthindex` for line width limiting)
- Optional: `luaunit` for running tests, `luacov` for coverage analysis

**C Implementation:**
- C89-compatible compiler (GCC, Clang, MSVC)
- Lua 5.1+ headers for Lua bindings
- Optional: `lcov` for coverage reports

### Building

**Lua (No build required):**
```bash
# Install dependencies
luarocks install luautf8

# Copy ariadne.lua to your project
cp ariadne.lua /path/to/your/project/
```

**C Library with Lua Bindings:**
```bash
# Compile shared library
gcc -O3 -Wall -shared -fPIC -o musubi.so musubi.c -llua

# Or with coverage instrumentation
gcc -shared -fPIC --coverage -o musubi.so musubi.c -llua
```

**macOS:**
```bash
gcc -O3 -Wall -shared -undefined dynamic_lookup -o musubi.so musubi.c
```

---

## Quick Start

### Basic Usage (C Bindings)

```lua
local mu = require "musubi"

-- Create a color generator for automatic color cycling
local cg = mu.colorgen()

-- Build a report
local report = mu.report(14)  -- Primary error position
    :title("Error", "Something went wrong")
    :code("E001")
    :label(14, 14):message("This is the problem"):color(cg:next())
    :note("Try fixing this by...")
    :source("local x = 10 + 'hello'", "example.js")
    :render()

print(report)
```

### Configuration

```lua
local mu = require "musubi"
local cfg = mu.config()
    :compact(true)            -- Enable compact mode
    :cross_gap(true)          -- Draw arrows across line gaps
    :tab_width(4)             -- Tab expansion width
    :limit_width(80)          -- Truncate long lines to 80 columns
    :char_set "unicode"       -- Use Unicode box-drawing characters
    :index_type "char"        -- Use character offsets (vs "byte")
    :ambiwidth(1)             -- Ambiguous character width (1 or 2)

mu.report(0)
    :config(cfg)
    -- ... rest of report
```

### Multi-Source Files

```lua
local mu = require "musubi"

mu.report(0)
    :label(10, 20, 1):message("Defined here")  -- src_id=1, first source
    :label(50, 60, 2):message("Used here")     -- src_id=2, second source
    :source("fn foo() { ... }", "foo.rs")
    :source("fn bar() { foo(); }", "bar.rs")
    :render()
```

### File Sources (C Bindings Only)

```lua
local mu = require "musubi"
local io = require "io"

local fp = io.open("large_file.txt", "r")
mu.report(0)
    :source(fp, "large_file.txt")  -- Streams file on-demand
    :label(100, 150):message("Error in large file")
    :render()
```

**Notice** that if you use file handle on Windows, the `musubi.so` must not be built as static linking (`/MT`).

---

## API Reference

### Report Builder

| Method                             | Description                                                        |
| ---------------------------------- | ------------------------------------------------------------------ |
| `mu.report(pos, src_id?)`          | Create a new report at position `pos`                              |
| `:title(level, message)`           | Set report level (`"Error"`, `"Warning"`) and title                |
| `:code(code)`                      | Set optional error code (e.g., `"E0308"`)                          |
| `:label(start, end?, src_id?)`     | Add a label span (half-open interval `[start, end)`)               |
| `:message(text, width?)`           | Attach message to the last added label                             |
| `:color(color)`                    | Set color for the last added label                                 |
| `:order(n)`                        | Set display order for the last label                               |
| `:priority(n)`                     | Set priority for clustering                                        |
| `:note(text)`                      | Add a note to the footer                                           |
| `:help(text)`                      | Add a help message to the footer                                   |
| `:source(content, name?, offset?)` | Register a source (string or FILE*) with line offset (`0` default) |
| `:render(writer?)`                 | Render the report (returns string or calls writer function)        |

### Configuration

| Option             | Type    | Default     | Description                                             |
| ------------------ | ------- | ----------- | ------------------------------------------------------- |
| `compact`          | boolean | `false`     | Hide empty lines between labels                         |
| `cross_gap`        | boolean | `true`      | Draw arrows across skipped lines                        |
| `underlines`       | boolean | `true`      | Draw underlines for single-line labels                  |
| `multiline_arrows` | boolean | `true`      | Use arrows for multi-line spans                         |
| `tab_width`        | integer | `4`         | Number of spaces per tab                                |
| `limit_width`      | integer | `0`         | Max line width (0 = unlimited)                          |
| `ambiwidth`        | integer | `1`         | Width of ambiguous Unicode characters                   |
| `label_attach`     | string  | `"middle"`  | Label attachment point (`"start"`, `"middle"`, `"end"`) |
| `index_type`       | string  | `"char"`    | Position indexing (`"char"` or `"byte"`)                |
| `char_set`         | string  | `"unicode"` | Glyph set (`"unicode"` or `"ascii"`)                    |
| `color`            | boolean | `true`      | Enable ANSI color codes                                 |

### Color Generator

```lua
local cg = mu.colorgen(min_brightness?)  -- min_brightness ∈ [0, 1], default 0.5
local color_func = cg:next()             -- Get next color in cycle
```

---

## Architecture

### Rendering Pipeline

```
Report:render()
  ├─ Context Creation (group labels by source, calculate widths)
  ├─ Header Rendering (error level, code, message)
  ├─ For each source group:
  │   ├─ Reference Header (file:line:col)
  │   ├─ Line Rendering:
  │   │   ├─ Label Clustering (group overlapping labels)
  │   │   ├─ Window Calculation (when limit_width > 0)
  │   │   ├─ Virtual Row Splitting (multi-line labels)
  │   │   └─ For each cluster:
  │   │       ├─ Line Content (with label highlighting)
  │   │       └─ Arrow Drawing (underlines, connectors, messages)
  │   └─ Empty Line
  └─ Footer Rendering (notes, help messages)
```

### Key Design Decisions

**Intervals:**

- All position named `start`/`end` use **half-open intervals** `[start, end)`
- All position named `first`/`last` use **close intervals** `[fist, last]`

**Width Caching:**

- Pre-compute cumulative display widths for each line
- Binary search (`muC_widthindex`) for O(log n) position lookups
- Handles UTF-8 multi-byte characters, Emoji, RI, CJK double-width, tabs

**Label Clustering:**

- Group overlapping/nearby labels into virtual rows
- Separate inline labels (single line) from multiline labels
- Dynamic column range calculation for windowing

**Memory Management (C):**
- Caller provides allocator function (defaults to `malloc`/`free`)
- Dynamic arrays with geometric growth (muA_* macros)
- External pointers (messages, source names) must outlive render call

---

## Testing

### Running Tests

**Lua Implementation:**
```bash
lua test.lua                # Run all 83 tests
REF=1 lua test.lua          # Use reference Lua implementation
lua -lluacov test.lua       # Collect coverage data
luacov ariadne.lua          # Generate coverage report
```

**C Implementation:**
```bash
# Compile with coverage
gcc -ggdb -shared --coverage -o musubi.so musubi.c

# Run tests (uses C bindings by default)
lua test.lua

# Generate coverage report
lcov -d . -c -o lcov.info
genhtml lcov.info -o coverage/
```

### Test Coverage

Both implementations maintain **100% test coverage**:
- 95 test cases covering all rendering paths
- Edge cases: zero-width spans, CJK characters, tab expansion, window truncation
- Regression tests for all fixed bugs
- Pixel-perfect output verification (2400+ lines of expected output)

**Test Categories:**
- Basic rendering (labels, messages, colors)
- Multi-line spans and clustering
- Line width limiting and windowing
- Unicode and CJK character handling
- Configuration options (compact, cross_gap, etc.)
- Multi-source file support
- File streaming (C only)

---

## Implementation Notes

### Differences from Rust Ariadne

**Improvements:**
- Cleaner margin render handling
- Explicit virtual row rendering for multi-line labels
- Width-based windowing with binary search optimization
- Label without message supports

**Limitations:**
- Only supports `\n` newlines (not Unicode line separators)
- Not full [UAX#29](https://www.unicode.org/reports/tr29/) grapheme cluster breaking (only support ZWJ & RI now)

### C Port Details

See [`.github/c_port.md`](.github/c_port.md) for detailed implementation notes:
- API constraints and call ordering requirements
- Memory management and lifetime rules
- UTF-8 handling and Unicode width calculations
- Source lifecycle and file streaming
- Known limitations and edge cases

### Project Structure

See [`.github/project-structure.md`](.github/project-structure.md) for:
- Detailed architecture documentation
- Data structure definitions
- Rendering algorithm explanations
- Bug fix history and rationale

---

## Contributing

Contributions are welcome! Please:

1. **Run tests** before submitting: `lua test.lua`
2. **Maintain 100% coverage**: Add tests for new features
3. **Follow existing style**: Lua uses tabs, C uses 4 spaces
4. **Update documentation**: Keep README and .github/*.md in sync

### Development Workflow

```bash
# Run tests with coverage
lua -lluacov test.lua
luacov ariadne.lua

# Find uncovered lines
grep '^\*\+0 ' luacov.report.out

# Run specific test
lua test.lua TestBasic.test_simple_label
```

---

## License

MIT License - See [LICENSE](LICENSE) for details.

---

## Credits

- Original Ariadne library: [zesterer/ariadne](https://github.com/zesterer/ariadne)
- UTF-8 support: [starwing/luautf8](https://github.com/starwing/luautf8)
- Test framework: [LuaUnit](https://github.com/bluebird75/luaunit)

---

## Related Projects

- [Ariadne (Rust)](https://github.com/zesterer/ariadne) - Original implementation
- [Annotate Snippets (Rust)](https://github.com/rust-lang/annotate-snippets-rs) - Similar project
- [Miette (Rust)](https://github.com/zkat/miette) - Fancy diagnostics library
- [Codespan (Rust)](https://github.com/brendanzab/codespan) - Alternative approach

---

<div align="center">

**Made with ❤️ for better compiler diagnostics**

[⬆ Back to Top](#musubi)

</div>
