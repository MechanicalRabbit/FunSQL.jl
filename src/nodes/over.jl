# Over node.

mutable struct OverNode <: TabularNode
    over::Union{SQLNode, Nothing}
    arg::SQLNode
    materialized::Union{Bool, Nothing}

    WithThisNode(; over = nothing, arg, materialized = nothing) =
        new(over, arg, materialized)
end

OverNode(arg; over = nothing, materialized = nothing) =
    WithThisNode(over = over, arg = arg, materialized = materialized)

"""
    Over(; over = nothing, arg, materialized = nothing)
    Over(arg; over = nothing, materialized = nothing)

`base |> Over(arg)` is an alias for `With(base, over = arg)`.
"""
Over(args...; kws...) =
    OverNode(args...; kws...) |> SQLNode

const var"funsql#over" = Over

dissect(scr::Symbol, ::typeof(Over), pats::Vector{Any}) =
    dissect(scr, OverNode, pats)

function PrettyPrinting.quoteof(n::OverNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Over), quoteof(n.arg, ctx))
    if n.materialized !== nothing
        push!(ex.args, Expr(:kw, :materialized, n.materialized))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::OverNode) =
    label(n.arg)

rebase(n::OverNode, n′) =
    OverNode(over = rebase(n.over, n′), arg = n.arg, materialized = n.materialized)
