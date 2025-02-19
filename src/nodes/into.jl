# Wrap the output into a nested record.

mutable struct IntoNode <: TabularNode
    name::Symbol

    IntoNode(; name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

IntoNode(name) =
    IntoNode(; name)

"""
    Into(; name, tail = nothing)
    Into(name; tail = nothing)

`Into` wraps output columns in a nested record.
"""
const Into = SQLQueryCtor{IntoNode}(:Into)

const funsql_into = Into

function PrettyPrinting.quoteof(n::IntoNode, ctx::QuoteContext)
    Expr(:call, :Into, quoteof(n.name))
end

label(n::IntoNode) =
    n.name
