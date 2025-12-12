<div align="center">

<h1>Musubi</h1>

**A beautiful diagnostics renderer for compiler errors and warnings**

![Language](https://img.shields.io/badge/language-Lua%20%7C%20C%20%7C%20Rust-blue)
[![Crates.io](https://img.shields.io/crates/v/musubi-rs)](https://crates.io/crates/musubi-rs)
[![docs.rs](https://img.shields.io/docsrs/musubi-rs)](https://docs.rs/musubi-rs)
![Version](https://img.shields.io/badge/version-0.4.0-green)
[![License](https://img.shields.io/badge/license-MIT-orange)](LICENSE)
[![Coverage Status](https://coveralls.io/repos/github/starwing/musubi/badge.svg?branch=master)](https://coveralls.io/github/starwing/musubi?branch=master)

[Overview](#overview) • [Key Features](#key-features) • [Installation](#installation) • [Quick Start](#quick-start) • [C API](#c-api-usage) • [Lua API](#lua-api-reference) • [Testing](#testing)

</div>

---

> **📦 For Rust Users**: This README covers the complete Musubi project (Lua/C/Rust implementations).  
> **Looking for Rust API documentation?** → See the comprehensive [Rust API docs](https://docs.rs/musubi-rs) with examples and usage guides.  
> **Rust crate**: [`musubi-rs`](https://crates.io/crates/musubi-rs)

---

## Overview

**Musubi** (結び, "connection" in Japanese) is a high-performance diagnostics renderer inspired by Rust's [Ariadne](https://github.com/zesterer/ariadne) library. It produces beautiful, color-coded diagnostic messages with precise source location highlighting, multi-line spans, and intelligent label clustering.

Originally ported from Rust's Ariadne library, Musubi has evolved into a production-ready **multi-language** implementation:
- **C Library**: High-performance core with Lua bindings (`musubi.h`, `musubi.c`)
- **Rust Crate**: Safe FFI wrapper with ergonomic builder API (`musubi-rs`)

Both implementations produce **identical output** and are thoroughly tested (26 Rust unit tests + 30 doc tests, 100 Lua tests).

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

**Rust Crate:**
- Rust 1.56+ (edition 2024)
- No external dependencies (self-contained C implementation)

**C Library with Lua Bindings:**
- C89-compatible compiler (GCC, Clang, MSVC)
- Lua 5.1+ headers for Lua bindings
- Optional: `lcov` for coverage reports

### Building

**Rust:**
```bash
cargo add musubi-rs
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

### Basic Usage (Lua Bindings)

```lua
local mu = require "musubi"

-- Create a color generator for automatic color cycling
local cg = mu.colorgen()

-- Build a report with inline source
local report = mu.report()
    :title("Error", "Something went wrong")
    :code("E001")
    :location(14)  -- Set header location
    :label(14, 20):message("This is the problem"):color(cg:next())
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
    :ambi_width(1)            -- Ambiguous character width (1 or 2)
    :column_order(false)      -- Use natural label ordering (default)
    :align_messages(true)     -- Align label messages (default)

mu.report(0)
    :config(cfg)
    -- ... rest of report
```

### Multi-Source Files

```lua
local mu = require "musubi"

-- Method 1: Using Cache (recommended for multiple sources)
local cache = mu.cache()
    :source("fn foo() { ... }", "foo.rs")   -- Source ID 0
    :source("fn bar() { foo(); }", "bar.rs") -- Source ID 1

local report = mu.report()
    :title("Error", "Undefined reference")
    :location(50, 1)  -- Header shows bar.rs:50
    :label(10, 20, 0):message("Defined here")
    :label(50, 60, 1):message("Used here")

cache:render(report)
print(report)

-- Method 2: Inline sources (also works, auto-creates cache)
mu.report()
    :title("Error", "Cross-file error")
    :location(10, 0)
    :label(10, 20, 0):message("Defined here")
    :label(50, 60, 1):message("Used here")
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

## C API Usage

**musubi is an [stb-style] single-header library**. You only need `musubi.h` - no separate compilation or linking required. Also see [sokol] for more examples of stb-style libraries.

[stb-style]: https://github.com/nothings/stb
[sokol]: https://github.com/floooh/sokol

### Setup

**In ONE C/C++ file** (typically your main file), define `MU_IMPLEMENTATION` before including:

```c
#define MU_IMPLEMENTATION
#include "musubi.h"
```

**In all other files**, just include the header normally:

```c
#include "musubi.h"  // Only declarations, no implementation
```

**For single-file projects**, use `MU_STATIC_API` to make all functions static:

```c
#define MU_STATIC_API  // Automatically defines MU_IMPLEMENTATION
#include "musubi.h"
```

### Basic Example

```c
#define MU_IMPLEMENTATION
#include <stdio.h>
#include <string.h>

#include "musubi.h"

static int stdout_writer(void *ud, const char *data, size_t len) {
    fwrite(data, 1, len, stdout);
    return 0; /* Success */
}

int main(void) {
    mu_Report   *R;
    mu_Cache    *C = NULL;
    mu_ColorGen  cg;
    mu_ColorCode color1;

    /* Initialize color generator */
    mu_initcolorgen(&cg, 0.5f);
    mu_gencolor(&cg, &color1);

    /* Create Cache and add a source */
    mu_addmemory(&C, mu_literal("local x = 10 + 'hello'"),
                 mu_literal("example.lua"));

    /* Create Report and configure */
    R = mu_new(NULL, NULL); /* NULL, NULL = use default malloc */
    mu_title(R, MU_ERROR, mu_literal(""), mu_literal("Type mismatch"));
    mu_code(R, mu_literal("E001"));
    mu_location(R, 14, 0); /* Position 14 in source 0 for header display */

    /* Add a label with message and color */
    mu_label(R, 15, 22, 0);
    mu_message(R, mu_literal("expected number, got string"), 0);
    mu_color(R, mu_fromcolorcode, &color1);

    /* Render to stdout */
    mu_writer(R, stdout_writer, NULL);
    mu_render(R, C);

    /* Cleanup */
    mu_delete(R);
    mu_delcache(C);
    return 0;
}
```

### Source/Cache Lifecycle

**Key Concept**: `mu_Source` IS-A `mu_Cache`. A single Source can be used wherever Cache is expected:

```c
mu_Cache  *C = NULL;                             /* Start with NULL Cache */
mu_Source *S = mu_addmemory(&C, content, name);  /* Auto-upgrades C if needed */
mu_render(R, (mu_Cache*)S);                      /* Source can be used as Cache */

mu_render(R, C); /* Or use C directly, as it have been updated with same source */
```

**Auto-Upgrade Mechanism**:
- First source: `mu_addmemory(&C, ...)` where `C == NULL` creates a single Source
- Second source: `mu_addmemory(&C, ...)` automatically upgrades to multi-Source Cache
- Transparent to user: always use `mu_addsource(&C, ...)` with double pointer

**Lifecycle Management**:
1. Create Cache: `C = mu_newcache(allocf, ud)` with allocator or start with `C = NULL`
2. Add sources: `mu_addmemory(&C, ...)` or `mu_addfile(&C, ...)`
3. Render: `mu_render(R, C)` uses Cache to fetch source lines
4. Cleanup: `mu_delcache(C)` frees Cache and all Sources

**Ownership Rules**:
- Cache owns all Sources added via `mu_addmemory` / `mu_addfile`
- Report does NOT own Cache - you must call `mu_delcache(C)` manually
- All string slices (`mu_Slice`) must outlive `mu_render()` call

### Multi-Source Example

```c
mu_Cache *C = NULL;  /* Start with NULL */
mu_Source *S1 = mu_addmemory(&C, mu_lslice("fn foo() { }", 12), 
                             mu_lslice("foo.c", 5));
mu_Source *S2 = mu_addmemory(&C, mu_lslice("fn bar() { foo(); }", 19), 
                             mu_lslice("bar.c", 5));

/* Cross-file diagnostic */
mu_Report *R = mu_new(NULL, NULL);
mu_title(R, MU_ERROR, mu_literal(""), mu_literal("Undefined reference"));
mu_location(R, 11, 1);   /* Header shows bar.c:11 (source id 1) */
mu_label(R, 11, 14, 1);  /* bar.c: source id 1 */
mu_message(R, mu_literal("called here"), 0);
mu_label(R, 3, 6, 0);    /* foo.c: source id 0 */
mu_message(R, mu_literal("defined here"), 0);
mu_writer(R, stdout_writer, NULL);  /* See Basic Example for stdout_writer */
mu_render(R, C); /* Render with cache */
mu_delete(R);
mu_delcache(C);  /* Frees both S1 and S2 */
```

### File Streaming

For large files, use `mu_addfile` to stream content on-demand:

```c
mu_Cache *C = NULL;
FILE *fp = fopen("large_file.c", "r");
mu_Source *S = mu_addfile(&C, fp, mu_lslice("large_file.c", 12));
/* musubi reads lines only when needed for rendering */
mu_location(R, pos, 0);  /* Optional: set header location */
mu_render(R, C);
fclose(fp);  /* Close after rendering */
mu_delcache(C);
```

**Important**: 
- File must remain open during `mu_render()` call
- `mu_addfile(&C, NULL, path)` opens file internally - musubi will close it on `mu_delcache()`
- When passing your own `FILE*`, you must close it yourself after rendering

### Error Handling

All API functions return `int` error codes:

```c
int err;

err = mu_label(R, 10, 20, 0);
if (err != MU_OK) {
    switch (err) {
        case MU_ERRPARAM: fprintf(stderr, "Invalid parameter\n"); break;
        case MU_ERRSRC:   fprintf(stderr, "Source not found\n"); break;
        case MU_ERRFILE:  fprintf(stderr, "File I/O error\n"); break;
    }
    mu_delete(R);
    return 1;
}

err = mu_render(R, C);
if (err != MU_OK) {
    /* Handle error */
}
```

### Custom Allocators

Provide custom allocator for memory control:

```c
void* my_alloc(void *ud, void *ptr, size_t nsize, size_t osize) {
    void *newptr;
    if (nsize == 0) {
        free(ptr);
        return NULL;
    }
    newptr = realloc(ptr, nsize);
    if (newptr == NULL) {
        /* handle out-of-memory yourself, or musubi may abort */
    }
    return newptr;
}

void *my_userdata = /* your context */;
mu_Cache *C = mu_newcache(my_alloc, my_userdata);
mu_Report *R = mu_new(my_alloc, my_userdata);
```

If alloc fails (returns NULL), you must jumps out of current flow (e.g., longjmp), or musubi may abort due to out-of-memory.

**Allocator signature**: `void* (*mu_Allocf)(void *ud, void *ptr, size_t nsize, size_t osize)`
- `ptr == NULL`: Allocate `nsize` bytes
- `nsize == 0`: Free `ptr` (allocated with `osize` bytes)
- Otherwise: Reallocate `ptr` from `osize` to `nsize` bytes

### C API Reference

**Types**:
- `mu_Report` - Diagnostic report builder
- `mu_Cache` - Multi-source container
- `mu_Source` - Single source (can be used as Cache)
- `mu_Slice` - String slice `{const char *p, *e}`
- `mu_ColorGen` - Color generator state
- `mu_ColorCode` - Pre-generated color code buffer `char[32]`
- `mu_Allocf` - Allocator function type
- `mu_Writer` - Output writer function type `int (*)(void *ud, const char *data, size_t len)`
- `mu_Color` - Color generator function type `mu_Chunk (*)(void *ud, mu_ColorKind kind)`

**Cache Management**:
- `mu_Cache* mu_newcache(mu_Allocf *allocf, void *ud)` - Create empty Cache
- `void mu_delcache(mu_Cache *C)` - Free Cache and all Sources
- `mu_Source* mu_addmemory(mu_Cache **pC, mu_Slice content, mu_Slice name)` - Add in-memory source
- `mu_Source* mu_addfile(mu_Cache **pC, FILE *fp, mu_Slice path)` - Add file source
- `unsigned mu_sourcecount(const mu_Cache *C)` - Get number of sources

**Report Building**:
- `mu_Report* mu_new(mu_Allocf *allocf, void *ud)` - Create new Report
- `void mu_delete(mu_Report *R)` - Free Report
- `void mu_reset(mu_Report *R)` - Reset Report for reuse
- `int mu_title(mu_Report *R, mu_Level level, mu_Slice custom, mu_Slice msg)` - Set kind and title
- `int mu_code(mu_Report *R, mu_Slice code)` - Set error code
- `int mu_location(mu_Report *R, size_t pos, mu_Id src_id)` - Set primary location for header display
- `int mu_label(mu_Report *R, size_t start, size_t end, mu_Id src_id)` - Add label span
- `int mu_message(mu_Report *R, mu_Slice msg, int width)` - Set message for last label
- `int mu_color(mu_Report *R, mu_Color *color, void *ud)` - Set color function for last label
- `int mu_order(mu_Report *R, int order)` - Set order for last label
- `int mu_priority(mu_Report *R, int priority)` - Set priority for last label
- `int mu_note(mu_Report *R, mu_Slice note)` - Add footer note
- `int mu_help(mu_Report *R, mu_Slice help)` - Add help text

**Rendering**:
- `int mu_writer(mu_Report *R, mu_Writer *fn, void *ud)` - Set output writer function
- `int mu_render(mu_Report *R, const mu_Cache *C)` - Render diagnostic

**Configuration**:
- `void mu_initconfig(mu_Config *cfg)` - Initialize config with defaults
- `int mu_config(mu_Report *R, const mu_Config *cfg)` - Apply configuration

**Color Generation**:
- `void mu_initcolorgen(mu_ColorGen *cg, float min_brightness)` - Initialize color generator
- `void mu_gencolor(mu_ColorGen *cg, mu_ColorCode *out)` - Generate next color code
- `mu_Chunk mu_fromcolorcode(void *ud, mu_ColorKind kind)` - Color function for pre-generated codes
- `mu_Chunk mu_default_color(void *ud, mu_ColorKind kind)` - Default color scheme

**Utilities**:
- `mu_Slice mu_lslice(const char *s, size_t len)` - Create slice with explicit length
- `mu_literal("text")` - Macro: create slice from string literal (compile-time length)
- `mu_slice(str)` - Macro: create slice from C string (uses `strlen`)

**Constants**:
- Error codes: `MU_OK` (0), `MU_ERRPARAM` (-1), `MU_ERRSRC` (-2), `MU_ERRLINE` (-3), `MU_ERRFILE` (-4)
- Levels: `MU_ERROR`, `MU_WARNING`, `MU_CUSTOM_LEVEL`

**For complete API documentation**, see `musubi.h` header file and [`.github/c_port.md`](.github/c_port.md).

---

## Lua API Reference

### Report Builder

| Method                             | Description                                                        |
| ---------------------------------- | ------------------------------------------------------------------ |
| `mu.report(pos?, src_id?)`         | Create a new report at optional position `pos`                     |
| `:title(level, message)`           | Set report level (`"Error"`, `"Warning"`) and title                |
| `:code(code)`                      | Set optional error code (e.g., `"E0308"`)                          |
| `:location(pos, src_id?)`          | Set primary location for header display                            |
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
| `compact`          | boolean | `false`     | Compact mode (works with underlines)                    |
| `cross_gap`        | boolean | `true`      | Draw arrows across skipped lines                        |
| `underlines`       | boolean | `true`      | Draw underlines for single-line labels                  |
| `column_order`     | boolean | `false`     | Simple column order (true) vs natural ordering (false)  |
| `align_messages`   | boolean | `true`      | Align label messages to same column                     |
| `multiline_arrows` | boolean | `true`      | Use arrows for multi-line spans                         |
| `tab_width`        | integer | `4`         | Number of spaces per tab                                |
| `limit_width`      | integer | `0`         | Max line width (0 = unlimited)                          |
| `ambi_width`       | integer | `1`         | Width of ambiguous Unicode characters                   |
| `label_attach`     | string  | `"middle"`  | Label attachment point (`"start"`, `"middle"`, `"end"`) |
| `index_type`       | string  | `"char"`    | Position indexing (`"char"` or `"byte"`)                |
| `char_set`         | string  | `"unicode"` | Glyph set (`"unicode"` or `"ascii"`)                    |
| `color`            | boolean | `true`      | Enable ANSI color codes                                 |

### Cache API

`mu.cache()` manages multiple source files for cross-file diagnostics. Each source is assigned an ID based on registration order (1, 2, ...).

#### Creating a Cache

```lua
local cache = mu.cache()  -- Create empty cache
```

#### Adding Sources

| Method                             | Description                                             |
| ---------------------------------- | ------------------------------------------------------- |
| `:source(content, name?, offset?)` | Add in-memory source (string) with optional line offset |
| `:file(path, offset?)`             | Load source from file system with optional line offset  |

```lua
local cache = mu.cache()
    :source("local x = 1 + '2'", "main.lua")     -- Source ID 1
    :source("fn bar() { foo(); }", "bar.rs")     -- Source ID 2
    :file("lib.lua")                             -- Source ID 3 (loads from filesystem)
```

#### Rendering with Cache

**Method 1: Cache renders report** (recommended for multi-source diagnostics):

```lua
local cache = mu.cache()
    :source("import foo", "main.py")
    :source("def foo(): pass", "lib.py")

local report = mu.report()
    :title("Error", "Import error")
    :location(7, 0)                    -- Header shows main.py:7
    :label(7, 10, 0):message("imported here")
    :label(4, 7, 1):message("defined here")

cache:render(report)  -- Cache provides sources to report
print(report)         -- Get rendered output
```

**Method 2: Report with inline sources** (convenience for single source):

```lua
local report = mu.report()
    :title("Error", "Syntax error")
    :label(0, 3):message("unexpected token")
    :source("let x = 42;", "main.rs")  -- Inline source registration
    :render()                          -- Returns rendered string

print(report)
```

#### Cache Properties

- **Length operator**: `#cache` returns the number of sources
- **Source IDs**: Assigned sequentially starting from 0
- **Lifetime**: Sources remain valid until cache is garbage collected

#### Multi-Source Example

```lua
local mu = require "musubi"
local cg = mu.colorgen()

-- Create cache with multiple files
local cache = mu.cache()
    :source("local function foo(x)\n  return x + 1\nend", "foo.lua")
    :source("local foo = require 'foo'\nprint(foo('hello'))", "main.lua")

-- Create report spanning both files
local report = mu.report()
    :title("Error", "Type mismatch")
    :location(25, 1)  -- Header shows main.lua:25
    :label(6, 9, 1):message("called with string"):color(cg:next())
    :label(19, 20, 0):message("expects number"):color(cg:next())
    :note("Function parameter type must match argument type")

-- Render using cache
cache:render(report)
print(report)
```

**For detailed Lua API documentation with examples**, see [`musubi.def.lua`](musubi.def.lua).

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
- 100 test cases covering all rendering paths
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

### C Implementation Details

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
