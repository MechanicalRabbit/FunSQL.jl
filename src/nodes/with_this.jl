# WithThis node.

mutable struct WithThisNode <: TabularNode
    over::Union{SQLNode, Nothing}
    arg::SQLNode
    materialized::Union{Bool, Nothing}

    WithThisNode(; over = nothing, arg, materialized = nothing) =
        new(over, arg, materialized)
end

WithThisNode(arg; over = nothing, materialized = nothing) =
    WithThisNode(over = over, arg = arg, materialized = materialized)

"""
    WithThis(; over = nothing, arg, materialized = nothing)
    WithThis(arg; over = nothing, materialized = nothing)

`over |> WithThis(then)` is an alias for `then |> With(over)`.
"""
WithThis(args...; kws...) =
    WithThisNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(WithThis), pats::Vector{Any}) =
    dissect(scr, WithThisNode, pats)

function PrettyPrinting.quoteof(n::WithThisNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(WithThis), quoteof(n.arg, ctx))
    if n.materialized !== nothing
        push!(ex.args, Expr(:kw, :materialized, n.materialized))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::WithThisNode) =
    label(n.arg)

rebase(n::WithThisNode, n′) =
    WithThisNode(over = rebase(n.over, n′), arg = n.arg, materialized = n.materialized)

