# Binding query parameters.

mutable struct BindNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}

    BindNode(;
             over = nothing,
             list) =
        new(over, list)
end

BindNode(list...; over = nothing) =
    BindNode(over = over, list = SQLNode[list...])

"""
    Bind(; over = nothing; list)
    Bind(list...; over = nothing)

Bind a query parameter to make a correlated subquery.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id]);

julia> visit_occurrence = SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id]);

julia> q = From(person) |>
           Where(Fun.exists(From(visit_occurrence) |>
                            Where(Get.person_id .== Var.person_id) |>
                            Bind(Get.person_id)));

julia> print(render(q))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
WHERE (EXISTS (
  SELECT NULL
  FROM "visit_occurrence" AS "visit_occurrence_1"
  WHERE ("visit_occurrence_1"."person_id" = "person_1"."person_id")
))
```
"""
Bind(args...; kws...) =
    BindNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Bind), pats::Vector{Any}) =
    dissect(scr, BindNode, pats)

function PrettyPrinting.quoteof(n::BindNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Bind))
    if isempty(n.list)
        push!(ex.args, Expr(:kw, :list, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.list, qctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

label(n::BindNode) =
    label(n.over)

rebase(n::BindNode, n′) =
    BindNode(over = rebase(n.over, n′), list = n.list)

