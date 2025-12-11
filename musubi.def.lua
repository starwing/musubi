--- @meta musubi
---
--- Musubi: A beautiful diagnostics renderer for compiler errors and warnings
---
--- This library provides Lua bindings for the musubi C library, which renders
--- diagnostic messages similar to rustc and other modern compilers.
---
--- For detailed API documentation and examples, see this file.
--- For C API reference, see musubi.h header file.

-------------------------------------------------------------------------------
-- Color Types
-------------------------------------------------------------------------------

--- Color is a function that returns a rendered color string.
---
--- It takes a category indicating what part of the report is being colored,
--- such as "kind", "margin", "note", etc.
---
--- @alias Color fun(category: ColorCategory): string?

--- Color categories for different parts of the diagnostic output.
---
--- @alias ColorCategory
--- | "reset"           # Reset to default terminal color
--- | "error"           # Error level indicator
--- | "warning"         # Warning level indicator
--- | "kind"            # Error/Warning kind text
--- | "margin"          # Line number margin
--- | "skipped_margin"  # Skipped line indicator (...)
--- | "unimportant"     # Secondary/context text
--- | "note"            # Note/help message footer
--- | "label"           # Label text and arrows

-------------------------------------------------------------------------------
-- ColorGenerator
-------------------------------------------------------------------------------

--- Generates a sequence of visually distinct colors for labels.
---
--- Each call to `next()` returns a different color that is visually distinct
--- from previous colors. Useful for automatically coloring multiple labels
--- in the same diagnostic.
---
--- # Example
--- ```lua
--- local mu = require "musubi"
--- local cg = mu.colorgen(0.5)  -- min_brightness = 0.5
--- local color1 = cg:next()
--- local color2 = cg:next()  -- Different from color1
--- ```
---
--- @class ColorGenerator
--- @overload fun(min_brightness?: number): ColorGenerator
--- @field new fun(min_brightness?: number): ColorGenerator
--- @field next fun(self: ColorGenerator): Color
local ColorGenerator = {}

-------------------------------------------------------------------------------
-- Config
-------------------------------------------------------------------------------

--- Configuration for diagnostic rendering behavior.
---
--- Controls various aspects of how diagnostics are rendered, including:
--- - Visual style (compact, underlines, arrows)
--- - Label ordering and alignment
--- - Character width handling
--- - Color output
---
--- # Example
--- ```lua
--- local cfg = mu.config()
---     :compact(true)           -- More condensed output
---     :tab_width(4)            -- 4-space tabs
---     :limit_width(80)         -- Wrap at 80 columns
---     :column_order(false)     -- Natural label ordering (default)
---     :align_messages(true)    -- Align label messages (default)
--- ```
---
--- @class Config
--- @overload fun(opts?: table): Config
--- @field new fun(opts?: table): Config  # Create new config with optional table
--- @field cross_gap fun(self: Config, enable: boolean): Config  # Draw arrows across line gaps (default: true)
--- @field compact fun(self: Config, enable: boolean): Config  # Compact mode: merge underlines and arrows (default: false)
--- @field underlines fun(self: Config, enable: boolean): Config  # Draw ^^^ underlines for spans (default: true)
--- @field column_order fun(self: Config, enable: boolean): Config  # Simple column order vs natural ordering (default: false=natural)
--- @field align_messages fun(self: Config, enable: boolean): Config  # Align label messages to same column (default: true)
--- @field multiline_arrows fun(self: Config, enable: boolean): Config  # Draw arrows for multi-line spans (default: true)
--- @field tab_width fun(self: Config, width: integer): Config  # Tab expansion width in spaces (default: 4)
--- @field limit_width fun(self: Config, width?: integer): Config  # Max line width, 0=unlimited (default: 0)
--- @field ambi_width fun(self: Config, width: integer): Config  # Ambiguous character width: 1 or 2 (default: 1)
--- @field label_attach fun(self: Config, attach: "middle"|"start"|"end"): Config  # Label attachment point (default: "middle")
--- @field index_type fun(self: Config, index_type: "byte"|"char"): Config  # Position indexing type (default: "char")
--- @field color fun(self: Config, enable: boolean): Config  # Enable ANSI color codes (default: true)
--- @field char_set fun(self: Config, char_set: "ascii"|"unicode"): Config  # Glyph set for drawing (default: "unicode")
local Config = {}


-------------------------------------------------------------------------------
-- Report
-------------------------------------------------------------------------------

--- Diagnostic report builder.
---
--- Builds a single diagnostic with labels, messages, and optional help/notes.
--- Uses chaining pattern for configuration. Maintains an internal Cache to
--- hold all added sources.
---
--- # Lifecycle
--- 1. Create: `mu.report(pos, src_id)` where pos is error location
--- 2. Configure title: :title(kind, message) sets diagnostic kind and main message
--- 3. Add labels: :label(start, end) creates a span, then :message() to annotate it
--- 4. Render: :render(writer?) produces output string
---
--- # Example
--- ```lua
--- local mu = require "musubi"
--- local cg = mu.colorgen()
--- local r = mu.report(15, 0)  -- Position 15 in source 0
---     :title("error", "type mismatch")
---     :code("E0001")
---     :label(15, 18)              -- Span from 15 to 18
---         :message("expected number, found string")
---         :color(cg:next())       -- Use ColorGenerator for automatic colors
---     :help("cast the value to a number")
---
--- local src = r:source("local x = 1 + '2'", "test.lua")
--- local output = r:render()  -- Returns formatted diagnostic string
--- print(output)
--- ```
---
--- # Label Attachment
--- After calling :label(), subsequent calls to :message(), :color(), :order(),
--- :priority() apply to that label until the next :label() call or :render().
---
--- # Source Management
--- Report maintains an internal Cache. Sources added with :source()/:file()
--- are kept alive until the Report is garbage collected.
---
--- @class Report
--- @overload fun(pos?: integer, id?: string|integer): Report
--- @field new fun(pos?: integer, id?: string|integer): Report  # Create report at position in source id
--- @field delete fun(self: Report)  # Manually free resources (normally GC'd)
--- @field reset fun(self: Report): Report  # Clear all labels and config, keep sources
--- @field config fun(self: Report, config: Config): Report  # Set rendering config (optional, uses default if not called)
--- @field code fun(self: Report, code: string): Report  # Set diagnostic code (e.g., "E0001")
--- @field title fun(self: Report, kind: LevelKind, message: string): Report  # Set kind and main message
--- @field location fun(self: Report, pos: integer, src_id?: integer): Report  # Set primary location of diagnostic
--- @field label fun(self: Report, start: integer, end?: integer, src_id?: integer): Report  # Add label span (subsequent calls modify this label)
--- @field message fun(self: Report, message: string, width?: integer): Report  # Set message for current label
--- @field color fun(self: Report, color: Color|string|function): Report  # Set color for current label (Color object, code string, or function)
--- @field order fun(self: Report, order: integer): Report  # Set display order for current label
--- @field priority fun(self: Report, priority: integer): Report  # Set priority for current label
--- @field note fun(self: Report, note: string): Report  # Add footer note
--- @field help fun(self: Report, help: string): Report  # Add help text
--- @field source fun(self: Report, code: string|file*, name?: string, offset?: integer): Report  # Add in-memory or file source to internal Cache
--- @field file fun(self: Report, name: string, offset?: integer): Report  # Add file source to internal Cache
--- @field render fun(self: Report, writer?: function): string  # Render diagnostic (returns string if no writer, else calls writer(chunk) repeatedly)
local Report = {}

--- Level kinds for diagnostics.
--- @alias LevelKind
--- | "error"   # Error level
--- | "warning" # Warning level
--- | "advice"  # Advice/info level
--- | string    # Any other custom level string

-------------------------------------------------------------------------------
-- Cache
-------------------------------------------------------------------------------

--- Multi-source container for diagnostic rendering.
---
--- Cache holds multiple named sources (in-memory strings or files) and
--- provides them to Report.render() for cross-file diagnostics.
---
--- # Single Source Auto-Upgrade
--- A single Source can be used as a Cache directly (transparent to user).
--- When you add a second source, the Source automatically upgrades to a
--- multi-source Cache. This is handled internally via mu_addsource.
---
--- # Lifecycle
--- 1. Create: `mu.cache()` creates an empty Cache
--- 2. Add sources: :source(content, name) or :file(path)
--- 3. Pass to Report: cache:render(report) renders diagnostic
---
--- # Example (Multi-Source)
--- ```lua
--- local mu = require "musubi"
--- local cache = mu.cache()
---     :source("local x = 1 + '2'", "main.lua")
---     :source("function add(a, b) return a + b end", "lib.lua")
---
--- local r = mu.report(15, 0)  -- Position 15 in source 0 (main.lua)
---     :title("error", "type mismatch")
---     :label(15, 18):message("expected number")
---
--- print(cache:render(r))
--- ```
---
--- # Example (Single Source as Cache)
--- ```lua
--- -- Report internally uses a Cache, so single-source case is transparent
--- local r = mu.report(15, 0)
--- r:source("local x = 1 + '2'", "test.lua")
--- print(r:render())  -- Works just like cache:render(r)
--- ```
---
--- # Length Operator
--- `#cache` returns the number of sources (0 for empty Cache).
---
--- @class Cache
--- @overload fun(): Cache
--- @field new fun(): Cache  # Create empty Cache
--- @field delete fun(self: Cache)  # Manually free resources (normally GC'd)
--- @field source fun(self: Cache, code: string|file*, name?: string, offset?: integer): Cache  # Add in-memory source or file handle
--- @field file fun(self: Cache, name: string, offset?: integer): Cache  # Add file source by path
--- @field render fun(self: Cache, report: Report, writer?: function): string  # Render diagnostic with this Cache's sources
--- @operator len: integer  # Returns number of sources in Cache
local Cache = {}

---@class (exact) Musubi
return {
    colorgen = ColorGenerator,
    config = Config,
    report = Report,
    cache = Cache,
    version = "0.3.0"
}
