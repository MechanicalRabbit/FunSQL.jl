# Make SQL fun!

module FunSQL

using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof, tile_expr, literal
using OrderedCollections: OrderedDict

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

"""
    render(node; dialect = :default) :: String

Convert the given SQL node or clause object to a SQL string.
"""
function render
end

"""
Base error class for all errors raised by FunSQL.
"""
abstract type FunSQLError <: Exception
end

include("dissect.jl")
include("dialects.jl")
include("types.jl")
include("statements.jl")
include("entities.jl")
include("clauses.jl")
include("nodes.jl")
include("annotate.jl")
include("resolve.jl")
include("collapse.jl")
include("render.jl")

const Not = Fun.not
const And = Fun.and
const Or = Fun.or
const Like = Fun.like
const In = Fun."in"
const NotIn = Fun."not in"
const IsNull = Fun."is null"
const IsNotNull = Fun."is not null"
const Case = Fun.case
const Concat = Fun.concat
const Coalesce = Fun.coalesce

end
