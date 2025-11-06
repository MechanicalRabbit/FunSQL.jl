# Wrap the output into a nested record.

mutable struct IntoNode <: TabularNode
    name::Symbol
    private::Bool

    IntoNode(; name::Union{Symbol, AbstractString}, private::Bool = false) =
        new(Symbol(name), private)
end

IntoNode(name; private = false) =
    IntoNode(; name, private)

"""
    Into(; name, private = false, tail = nothing)
    Into(name; private = false, tail = nothing)

`Into` wraps output columns in a nested record.
"""
const Into = SQLQueryCtor{IntoNode}(:Into)

const funsql_into = Into

function PrettyPrinting.quoteof(n::IntoNode, ctx::QuoteContext)
    ex = Expr(:call, :Into, quoteof(n.name))
    if n.private
        push!(ex.args, Expr(:kw, :private, n.private))
    end
    ex
end

label(n::IntoNode) =
    n.name
