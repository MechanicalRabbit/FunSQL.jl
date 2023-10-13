# Make SQL fun!

module FunSQL

export
    @funsql,
    var"funsql#agg",
    var"funsql#append",
    var"funsql#as",
    var"funsql#asc",
    var"funsql#bind",
    var"funsql#cross_join",
    var"funsql#define",
    var"funsql#desc",
    var"funsql#filter",
    var"funsql#from",
    var"funsql#fun",
    var"funsql#group",
    var"funsql#highlight",
    var"funsql#iterate",
    var"funsql#join",
    var"funsql#left_join",
    var"funsql#limit",
    var"funsql#order",
    var"funsql#over",
    var"funsql#partition",
    var"funsql#select",
    var"funsql#sort",
    var"funsql#with"


using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof, tile_expr, literal
using OrderedCollections: OrderedDict, OrderedSet
using Tables
using DBInterface
using LRUCache

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

"""
Base error class for all errors raised by FunSQL.
"""
abstract type FunSQLError <: Exception
end

include("dissect.jl")
include("quote.jl")
include("strings.jl")
include("dialects.jl")
include("catalogs.jl")
include("clauses.jl")
include("nodes.jl")
include("connections.jl")
include("types.jl")
include("annotate.jl")
include("translate.jl")
include("serialize.jl")
include("render.jl")
include("reflect.jl")

end
