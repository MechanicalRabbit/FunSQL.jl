# Make SQL fun!

module FunSQL

using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

include("dialects.jl")
include("entities.jl")
include("clauses.jl")
include("nodes.jl")

end
