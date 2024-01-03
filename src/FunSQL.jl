# Make SQL fun!

module FunSQL

export
    @funsql,
    funsql_agg,
    funsql_append,
    funsql_as,
    funsql_asc,
    funsql_bind,
    funsql_cross_join,
    funsql_define,
    funsql_desc,
    funsql_filter,
    funsql_from,
    funsql_fun,
    funsql_group,
    funsql_highlight,
    funsql_iterate,
    funsql_join,
    funsql_left_join,
    funsql_limit,
    funsql_order,
    funsql_over,
    funsql_partition,
    funsql_select,
    funsql_sort,
    funsql_with


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
