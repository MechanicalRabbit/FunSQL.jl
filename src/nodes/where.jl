# Where node.

mutable struct WhereNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    condition::SQLNode

    WhereNode(; over = nothing, condition) =
        new(over, condition)
end

WhereNode(condition; over = nothing) =
    WhereNode(over = over, condition = condition)

Where(args...; kws...) =
    WhereNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::WhereNode; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call,
              wrap ? nameof(Where) : nameof(WhereNode),
              !limit ? quoteof(n.condition) : :…)
    if n.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(n.over), ex)
    end
    ex
end

rebase(n::WhereNode, n′) =
    WhereNode(over = rebase(n.over, n′), condition = n.condition)

