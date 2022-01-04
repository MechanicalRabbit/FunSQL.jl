# Binding query parameters.

mutable struct BindNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function BindNode(; over = nothing, args, label_map = nothing)
        if label_map !== nothing
            new(over, args, label_map)
        else
            n = new(over, args, OrderedDict{Symbol, Int}())
            populate_label_map!(n)
            n
        end
    end
end

BindNode(args...; over = nothing) =
    BindNode(over = over, args = SQLNode[args...])

"""
    Bind(; over = nothing; args)
    Bind(args...; over = nothing)

The `Bind` node binds the query parameters in an inner query to make it
a correlated subquery.

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

function PrettyPrinting.quoteof(n::BindNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Bind))
    if isempty(n.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.args, ctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::BindNode) =
    label(n.over)

rebase(n::BindNode, n′) =
    BindNode(over = rebase(n.over, n′), args = n.args)

