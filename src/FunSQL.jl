# Make SQL fun!

module FunSQL

using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof, tile_expr, literal

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

"""
    render(node; dialect = :default) :: String

Convert the given SQL node or clause object to a SQL string.
"""
function render
end

include("dissect.jl")
include("dialects.jl")
include("entities.jl")
include("clauses.jl")
include("nodes.jl")

end
