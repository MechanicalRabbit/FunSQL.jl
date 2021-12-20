# Recursive UNION ALL node.

mutable struct IterateNode <: TabularNode
    over::Union{SQLNode, Nothing}
    iterator::SQLNode

    IterateNode(; over = nothing, iterator) =
        new(over, iterator)
end

IterateNode(iterator; over = nothing) =
    IterateNode(over = over, iterator = iterator)

"""
    Iterate(; over = nothing, iterator)
    Iterate(iterator; over = nothing)
"""
Iterate(args...; kws...) =
    IterateNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Iterate), pats::Vector{Any}) =
    dissect(scr, IterateNode, pats)

function PrettyPrinting.quoteof(n::IterateNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Iterate))
    if !ctx.limit
        push!(ex.args, quoteof(n.iterator, ctx))
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::IterateNode) =
    label(n.over)

rebase(n::IterateNode, n′) =
    IterateNode(over = rebase(n.over, n′), iterator = n.iterator)

