# With node.

mutable struct WithNode <: TabularNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function WithNode(; over = nothing, list, label_map = nothing)
        if label_map !== nothing
            return new(over, list, label_map)
        end
        n = new(over, list, OrderedDict{Symbol, Int}())
        for (i, l) in enumerate(n.list)
            name = label(l)
            if name in keys(n.label_map)
                err = DuplicateLabelError(name, path = [l, n])
                throw(err)
            end
            n.label_map[name] = i
        end
        n
    end
end

WithNode(list...; over = nothing) =
    WithNode(over = over, list = SQLNode[list...])

"""
    With(; over = nothing, list)
    With(list...; over = nothing)
```
"""
With(args...; kws...) =
    WithNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(With), pats::Vector{Any}) =
    dissect(scr, WithNode, pats)

function PrettyPrinting.quoteof(n::WithNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(With))
    if isempty(n.list)
        push!(ex.args, Expr(:kw, :list, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.list, ctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::WithNode) =
    label(n.over)

rebase(n::WithNode, n′) =
    WithNode(over = rebase(n.over, n′), list = n.list)

