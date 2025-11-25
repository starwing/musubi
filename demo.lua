--- @class musubi.Report
--- @field code fun(self: musubi.Report, code: string): musubi.Report
--- @field title fun(self: musubi.Report, level: string, message: string): musubi.Report
--- @field label fun(self: musubi.Report, line: integer, column: integer): musubi.Report
--- @field message fun(self: musubi.Report, message: string): musubi.Report
--- @field color fun(self: musubi.Report, color: function): musubi.Report
--- @field note fun(self: musubi.Report, note: string): musubi.Report
--- @field source fun(self: musubi.Report, source: string, filename: string): musubi.Report
--- @field render fun(self: musubi.Report, writer?: fun(string):integer?): string

--- @class musubi.ColerGen
--- @field next fun(self: musubi.ColerGen): function

--- @class musubi
--- @field report fun(pos: integer, src_id?: integer): musubi.Report
--- @field colorgen fun(): musubi.ColerGen
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
