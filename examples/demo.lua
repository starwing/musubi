local mu = require "musubi"

local cg = mu.colorgen()

print(
    mu.report("Incompatible types")
    :code "3"
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
