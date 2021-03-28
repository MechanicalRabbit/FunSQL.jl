# From node.

mutable struct FromNode <: AbstractSQLNode
    table::SQLTable

    FromNode(; table) =
        new(table)
end

FromNode(table) =
    FromNode(table = table)

From(args...; kws...) =
    FromNode(args...; kws...) |> SQLNode

Base.convert(::Type{AbstractSQLNode}, table::SQLTable) =
    FromNode(table)

function PrettyPrinting.quoteof(n::FromNode; limit::Bool = false, wrap::Bool = false)
    Expr(:call,
         wrap ? nameof(From) : nameof(FromNode),
         !limit ? quoteof(n.table, limit=true) : :…)
end

