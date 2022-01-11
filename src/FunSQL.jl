# Make SQL fun!

module FunSQL

using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof, tile_expr, literal
using OrderedCollections: OrderedDict, OrderedSet
using Tables
using DBInterface
using LRUCache

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

"""
    render(node::Union{SQLNode, SQLClause}; dialect = :default)::SQLString

Serialize the given SQL node or SQL clause object.
"""
function render
end

"""
    reflect(conn; schema = nothing, dialect = :default)::Vector{SQLTable}

Retrieve a list of available database tables.
"""
function reflect
end

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
include("render.jl")
include("reflect.jl")

end
