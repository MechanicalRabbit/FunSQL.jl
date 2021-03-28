# Selecting.

mutable struct SelectNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}

    SelectNode(; over = nothing, list) =
        new(over, list)
end

SelectNode(list...; over = nothing) =
    SelectNode(over = over, list = SQLNode[list...])

Select(args...; kws...) =
    SelectNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::SelectNode; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(Select) : nameof(SelectNode))
    if !limit
        list_exs = Any[quoteof(item) for item in n.list]
        if isempty(n.list)
            push!(ex.args, Expr(:kw, :list, Expr(:vect, list_exs...)))
        else
            append!(ex.args, list_exs)
        end
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(n.over), ex)
    end
    ex
end

rebase(n::SelectNode, n′) =
    SelectNode(over = rebase(n.over, n′), list = n.list)

