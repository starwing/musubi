# C Port Implementation Notes

> **Status**: Core implementation complete, Lua bindings in progress  
> **Last Updated**: 2025-11-25

This document contains important implementation details, design decisions, and API constraints for the C port of the Ariadne diagnostics renderer (`musubi.h`).

---

## Table of Contents

- [Design Principles](#design-principles)
- [API Usage Constraints](#api-usage-constraints)
- [Memory Management](#memory-management)
- [UTF-8 and Unicode Handling](#utf-8-and-unicode-handling)
- [Interval Semantics](#interval-semantics)
- [Source Management](#source-management)
- [Known Limitations](#known-limitations)
- [Testing Status](#testing-status)

---

## Design Principles

### Core Philosophy

The C implementation follows these key principles:

1. **Zero-based indexing**: All positions, offsets, and indices use 0-based counting
2. **Half-open intervals**: Ranges use `[start, end)` semantics (includes start, excludes end)
3. **Minimal allocations**: Reuse buffers and arrays where possible
4. **Error propagation**: Use return codes (`MU_OK`, `MU_ERRPARAM`, etc.) instead of exceptions
5. **External lifetime management**: Caller is responsible for lifetime of passed pointers

### Alignment with Lua Implementation

- The C port maintains **semantic equivalence** with the Lua implementation
- Core rendering algorithms are identical (tested against the same expected outputs)
- API surface differs to accommodate C conventions (explicit memory management, type safety)

---

## API Usage Constraints

### ⚠️ Critical: API Call Ordering

The API **must** be called in this specific order:

```c
mu_Report *R = mu_new(allocf, ud);
mu_config(R, &config);           // MUST be called before mu_label()
mu_source(R, src);               // Add all sources
mu_label(R, start, end, src_id); // Add labels
mu_message(R, "...", -1);        // Attach messages to labels
mu_render(R, pos, src_id);       // Render the report
mu_delete(R);                    // Clean up
```

**Why this matters**:
- `mu_config()` sets `ambiwidth` used to calculate label message widths
- Calling `mu_config()` **after** `mu_label()/mu_message()` will cause:
  - Width calculations to use outdated `ambiwidth` values
  - Incorrect layout and text wrapping in rendered output
- **The implementation enforces this**: `mu_config()` returns `MU_ERRPARAM` if labels already exist

### Correct Usage

```c
mu_Config cfg;
mu_initconfig(&cfg);
cfg.ambiwidth = 2;  // Set before adding labels
mu_config(R, &cfg); // ✅ Call first

mu_label(R, 0, 10, 0);
mu_message(R, "测试", -1);  // Width calculated with ambiwidth=2
```

### Incorrect Usage (Will Fail)

```c
mu_label(R, 0, 10, 0);
mu_message(R, "测试", -1);

mu_Config cfg;
mu_initconfig(&cfg);
cfg.ambiwidth = 2;
mu_config(R, &cfg);  // ❌ Returns MU_ERRPARAM (labels already exist)
```

---

## Memory Management

### Allocator Function

All dynamic memory is managed through the user-provided allocator:

```c
typedef void *mu_Allocf(void *ud, void *p, size_t nsize, size_t osize);
```

**Contract**:
- `p == NULL, nsize > 0`: Allocate `nsize` bytes
- `p != NULL, nsize > 0`: Reallocate `p` to `nsize` bytes (old size = `osize`)
- `p != NULL, nsize == 0`: Free `p` (old size = `osize`)
- On allocation failure: **Must** either `abort()` or `longjmp()` (returning `NULL` is not supported)

**Default behavior**: If `allocf == NULL`, uses system `malloc/realloc/free` with `abort()` on OOM.

### Lifetime Management

#### External Pointers (User Responsibility)

The following pointers passed to the API are **not copied** and must remain valid until `mu_render()` completes:

1. **Source names** (`const char *name` in `mu_file_source()`, `mu_memory_source()`):
   - Must be **null-terminated C strings**
   - Must point to stable memory (not stack temporaries)
   - Used by `fopen()` internally for file sources

   ```c
   // ❌ WRONG: Stack-allocated string
   {
       char temp[100];
       snprintf(temp, sizeof(temp), "file_%d.txt", index);
       src = mu_file_source(R, NULL, temp);  // temp destroyed after scope!
   }
   
   // ✅ CORRECT: Static string or heap allocation
   src = mu_file_source(R, NULL, "input.txt");  // String literal OK
   ```

2. **Label messages** (`const char *msg` in `mu_message()`):
   - Same lifetime requirement as source names
   
3. **Help/Note strings** (`mu_help()`, `mu_note()`):
   - Same lifetime requirement

4. **Config struct** (`mu_Config *config` in `mu_config()`):
   - The `mu_Config*` pointer itself is stored (not copied)
   - Config must remain valid until `mu_render()` completes

#### Internal Memory (Managed by Report)

The following are owned by `mu_Report` and freed automatically:

- `mu_Source` objects (via `mu_newsource()`)
- `mu_Label` array
- Internal rendering buffers (groups, clusters, width cache, etc.)

### Reusing Reports

To reuse a `mu_Report` for multiple render operations:

```c
mu_Report *R = mu_new(NULL, NULL);
mu_config(R, &cfg);

// First report
mu_source(R, src1);
mu_label(R, ...);
mu_render(R, ...);

// Reuse for second report
mu_reset(R);            // Frees sources, clears labels
mu_config(R, &cfg);     // Reconfigure (if needed)
mu_source(R, src2);     // Add new sources
mu_label(R, ...);
mu_render(R, ...);

mu_delete(R);
```

**Note**: `mu_reset()` calls `src->free()` on all sources, so you must re-add them.

---

## UTF-8 and Unicode Handling

### Character Width Calculation

Character display widths follow Unicode standards:
- **ASCII**: Width 1
- **CJK characters**: Width 2
- **Combining marks**: Width 0
- **Ambiguous width characters**: Configurable via `config->ambiwidth` (1 or 2)

### Tab Expansion

Tabs are expanded to spaces based on `config->tab_width` (default 4):
- Tab at column 0-3 → expands to 4 spaces
- Tab at column 4-7 → expands to 4 spaces
- Formula: `spaces = tab_width - (column % tab_width)`

### Invalid UTF-8 Handling

- **In source files**: Invalid UTF-8 sequences are treated as single-byte characters (width 1)
- **At buffer boundaries**: Incomplete multi-byte sequences are carried over to the next read
  - Implementation uses `muD_checkend()` to detect incomplete sequences at buffer boundaries
  - Incomplete bytes are prepended to the next `fread()` buffer

---

## Interval Semantics

### General Rule: Half-Open Intervals

**All character/byte ranges use half-open intervals `[start, end)`**:
- `start` is **included**
- `end` is **excluded**

Examples:
```c
mu_label(R, 0, 5, 0);  // Covers characters at positions 0,1,2,3,4 (NOT 5)
```

### Special Exception: `muM_contains()` and Newline/EOF Positions

The function `muM_contains(pos, line)` allows `pos` to point **one past** the line end:
```c
// Returns true if: line->offset <= pos < line->offset + line->len + 1
static int muM_contains(unsigned pos, const mu_Line *line) {
    return pos >= line->offset && pos < line->offset + line->len + 1;
}
```

**Why the `+1`?**
- Allows labels to point to the newline character (`\n`) or EOF position
- Common in compiler diagnostics: "error after this line"
- Enables labels like `[line_end, line_end+1)` to highlight the invisible newline

**Implications**:
- Inline label collection (`muC_collect_inline`) uses `end_char <= line->offset + line->len + 1`
- Multi-line label termination (`muC_collect_multi`) uses `muM_contains(end_char, line)`
- Highlight calculation (`muC_update_highlight`) checks `pos > end_char + 1` for exclusion

---

## Source Management

### Source Lifecycle

1. **Creation**: User calls `mu_newsource()`, `mu_memory_source()`, or `mu_file_source()`
   - Memory allocated via `R->allocf`
   - `src->id` assigned automatically
   - `src->gidx` initialized to `MU_SRC_UNUSED` (-2)

2. **Registration**: User calls `mu_source(R, src)` to add source to report
   - Source added to `R->sources` array
   - Report takes ownership

3. **Initialization** (lazy):
   - First `mu_render()` that references the source calls `src->init(src)`
   - For file sources: reads entire file, builds line offset table
   - For memory sources: builds line offset table from in-memory data
   - `src->gidx` set to group index (>= 0)
   - **`init()` may NOT be called** if source is added but no labels reference it

4. **Destruction**:
   - `mu_reset(R)` or `mu_delete(R)` calls `src->free(src)` on all sources
   - User's source object is freed (via `mu_freesource()`)

### File Source Ownership

```c
mu_Source *src = mu_file_source(R, fp, name);
```

**If `fp == NULL`** (recommended):
- Implementation opens file via `fopen(name, "r")`
- Report owns the `FILE*` and closes it on `src->free()`

**If `fp != NULL`** (user-provided):
- Report **does not** close the `FILE*` on `src->free()`
- User must close `fp` manually after `mu_render()` completes

Example:
```c
// User manages FILE*
FILE *fp = fopen("input.txt", "r");
mu_Source *src = mu_file_source(R, fp, "input.txt");
mu_render(R, ...);
mu_delete(R);  // Does NOT close fp
fclose(fp);    // ✅ User must close

// Report manages FILE*
mu_Source *src = mu_file_source(R, NULL, "input.txt");
mu_render(R, ...);
mu_delete(R);  // ✅ Automatically closes file
```

### Large File Support

- **POSIX/Unix**: Uses `fseeko()` for 64-bit file offsets (supports files >2GB)
- **Windows**: Uses `_fseeki64()` for large file support
- **Fallback**: Standard `fseek()` with `long` offset (limited to ~2GB)
- Conditional compilation via `_POSIX_C_SOURCE` and `_WIN32` macros

---

## Known Limitations

### 1. No Support for Concurrent File Modification

If a source file is modified **after** `src->init()` but **before** rendering completes:
- Line offsets may be stale
- `fseek()` + `fread()` may return truncated/incorrect data
- `muC_fill_widthcache()` pads missing data with width-1 spaces to prevent crashes
- **Behavior**: Incorrect rendering (missing characters, wrong widths), not undefined behavior

**Mitigation**: Ensure source files are not modified during rendering.

### 2. Index Type Consistency

The `config->index_type` must match how label positions are specified:
- `MU_INDEX_BYTE`: Positions are byte offsets (0-based)
- `MU_INDEX_CHAR`: Positions are character offsets (0-based, UTF-8 aware)

**Mixing index types for different labels is not supported** and will cause incorrect rendering.

### 3. Ambiguous Width Character Handling

The `config->ambiwidth` setting applies globally to all sources:
- **Cannot** use different `ambiwidth` values for different files in the same report
- East Asian Ambiguous characters (e.g., Greek letters, box drawing) will use the same width everywhere

---

## Testing Status

### Core Rendering (100% Coverage)

All core rendering functions have been tested against the Lua implementation:
- ✅ Multi-line labels with margin arrows
- ✅ Inline labels with correct positioning
- ✅ Width-limited rendering (line windowing)
- ✅ Cluster splitting for wide diagnostics
- ✅ UTF-8 handling (CJK characters, combining marks)
- ✅ Tab expansion
- ✅ Color output (ANSI and Unicode glyphs)

### Source Implementation

- ✅ Memory sources (in-memory string data)
- ✅ File sources (buffered reading with UTF-8 boundary handling)
- ✅ Line offset calculation
- ✅ Character/byte index conversion

### API Construction

- ✅ Report creation and configuration
- ✅ Label addition and message attachment
- ✅ Source registration
- ✅ Error propagation
- 🚧 Lua bindings (in progress)

### Edge Cases Verified

1. ✅ Empty files and empty lines
2. ✅ Files without trailing newline
3. ✅ UTF-8 characters split across `BUFSIZ` boundaries
4. ✅ Label width calculation with `ambiwidth=1` vs `ambiwidth=2`
5. ✅ Zero-width labels (single position)
6. ✅ Labels spanning multiple sources (separate groups)

---

## Future Enhancements

### Planned for v1.0

- [ ] Complete Lua bindings (`musubi.lua` wrapper)
- [ ] Comprehensive README with C and Lua usage examples
- [ ] Performance benchmarks vs Lua implementation

### Under Consideration

- [ ] Streaming API for very large files (avoid full line table)
- [ ] Custom color schemes via config
- [ ] Thread-safe rendering (multiple reports in parallel)
- [ ] Support for non-file sources (sockets, pipes, etc.)

---

## References

- **Lua Implementation**: `ariadne.lua` (reference implementation)
- **Test Suite**: `test.lua` (55 tests, all passing against C port)
- **Project Structure**: `.github/project-structure.md` (architecture overview)
- **Development Roadmap**: `.github/roadmap.md` (feature tracking)
