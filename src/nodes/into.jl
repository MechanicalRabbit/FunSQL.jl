# Wrap the output into a nested record.

mutable struct IntoNode <: TabularNode
    over::Union{SQLNode, Nothing}
    name::Symbol

    IntoNode(;
           over = nothing,
           name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

IntoNode(name; over = nothing) =
    IntoNode(over = over, name = name)

"""
    Into(; over = nothing, name)
    Into(name; over = nothing)

`Into` wraps output columns in a nested record.
"""
Into(args...; kws...) =
    IntoNode(args...; kws...) |> SQLNode

const funsql_into = Into

dissect(scr::Symbol, ::typeof(Into), pats::Vector{Any}) =
    dissect(scr, IntoNode, pats)

function PrettyPrinting.quoteof(n::IntoNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Into), quoteof(n.name))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::IntoNode) =
    n.name
