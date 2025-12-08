--- @meta musubi

--- Color is a function that returns a rendered color string.  - It takes a
--- category. The category indicates what part of the report is being colored,
--- such as "kind", "margin", "note", etc.
--- "reset" is a special category that indicates resetting to default color.
--- @alias Color fun(category: ColorCategory): string?

--- @alias ColorCategory
--- | "reset"
--- | "error"
--- | "warning"
--- | "kind"
--- | "margin"
--- | "skipped_margin"
--- | "unimportant"
--- | "note"
--- | "label"

--- @class ColorGenerator
--- @overload fun(min_brightness?: number): ColorGenerator
--- @field new fun(min_brightness?: number): ColorGenerator
--- @field next fun(self: ColorGenerator): Color
local ColorGenerator = {}

--- @class Config
--- @overload fun(opts?: table): Config
--- @field new fun(opts: table): Config
--- @field cross_gap fun(self: Config, enable: boolean): Config
--- @field compact fun(self: Config, enable: boolean): Config
--- @field underlines fun(self: Config, enable: boolean): Config
--- @field column_order fun(self: Config, enable: boolean): Config
--- @field align_messages fun(self: Config, enable: boolean): Config
--- @field multiline_arrows fun(self: Config, enable: boolean): Config
--- @field tab_width fun(self: Config, width: integer): Config
--- @field limit_width fun(self: Config, width?: integer): Config
--- @field ambi_width fun(self: Config, width: integer): Config
--- @field label_attach fun(self: Config, attach: "middle"|"start"|"end"): Config
--- @field index_type fun(self: Config, index_type: "byte"|"char"): Config
--- @field color fun(self: Config, color: boolean): Config
--- @field char_set fun(self: Config, char_set: string): Config
local Config = {}

--- @class Report
--- @field file fun(self: Report, name: string): Report
--- @overload fun(pos?: integer, id?: string|integer): Report
--- @field new fun(pos?: integer, id?: string|integer): Report
--- @field reset fun(self: Report): Report
--- @field config fun(self: Report, config: Config): Report
--- @field code fun(self: Report, code: string): Report
--- @field title fun(self: Report, kind: string, message: string): Report
--- @field label fun(self: Report, i: integer, j?: integer, src_id?: integer): Report
--- @field message fun(self: Report, message: string, width?: integer): Report
--- @field color fun(self: Report, color: Color): Report
--- @field order fun(self: Report, order: integer): Report
--- @field priority fun(self: Report, priority: integer): Report
--- @field note fun(self: Report, note: string): Report
--- @field help fun(self: Report, help: string): Report
--- @field source fun(self: Report, code: string|file*, name?: string, offset?: integer): Report
--- @field render fun(self: Report, writer?: fun(string)): string
local Report = {}

---@class (exact) Musubi
return {
    colorgen = ColorGenerator,
    config = Config,
    report = Report,
    version = "0.3.0"
}
