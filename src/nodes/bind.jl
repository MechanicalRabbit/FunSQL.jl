# Binding query parameters.

mutable struct BindNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function BindNode(; over = nothing, list, label_map = nothing)
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

BindNode(list...; over = nothing) =
    BindNode(over = over, list = SQLNode[list...])

"""
    Bind(; over = nothing; list)
    Bind(list...; over = nothing)

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

label(n::BindNode) =
    label(n.over)

rebase(n::BindNode, n′) =
    BindNode(over = rebase(n.over, n′), list = n.list)

