# With node.

mutable struct WithNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    materialized::Union{Bool, Nothing}
    label_map::OrderedDict{Symbol, Int}

    function WithNode(; over = nothing, args, materialized = nothing, label_map = nothing)
        if label_map !== nothing
            return new(over, args, materialized, label_map)
        end
        n = new(over, args, materialized, OrderedDict{Symbol, Int}())
        for (i, arg) in enumerate(n.args)
            name = label(arg)
            if name in keys(n.label_map)
                err = DuplicateLabelError(name, path = [arg, n])
                throw(err)
            end
            n.label_map[name] = i
        end
        n
    end
end

WithNode(args...; over = nothing, materialized = nothing) =
    WithNode(over = over, args = SQLNode[args...], materialized = materialized)

"""
    With(; over = nothing, args, materialized = nothing)
    With(args...; over = nothing, materialized = nothing)

`With` assigns a name to a temporary dataset.  This dataset could be
referred to by name in the `over` query.

```
WITH \$args...
SELECT ...
FROM \$over
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> condition_occurrence =
           SQLTable(:condition_occurrence, columns = [:condition_occurrence_id,
                                                      :person_id,
                                                      :condition_concept_id]);

julia> q = From(person) |>
           Where(Fun.in(Get.person_id, From(:essential_hypertension) |>
                                       Select(Get.person_id))) |>
           With(:essential_hypertension =>
                    From(condition_occurrence) |>
                    Where(Get.condition_concept_id .== 320128));

julia> print(render(q))
WITH "essential_hypertension_1" ("person_id") AS (
  SELECT "condition_occurrence_1"."person_id"
  FROM "condition_occurrence" AS "condition_occurrence_1"
  WHERE ("condition_occurrence_1"."condition_concept_id" = 320128)
)
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."person_id" IN (
  SELECT "essential_hypertension_1"."person_id"
  FROM "essential_hypertension_1"
))
```
"""
With(args...; kws...) =
    WithNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(With), pats::Vector{Any}) =
    dissect(scr, WithNode, pats)

function PrettyPrinting.quoteof(n::WithNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(With))
    if isempty(n.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.args, ctx))
    end
    if n.materialized !== nothing
        push!(ex.args, Expr(:kw, :materialized, n.materialized))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::WithNode) =
    label(n.over)

rebase(n::WithNode, n′) =
    WithNode(over = rebase(n.over, n′), args = n.args, materialized = n.materialized)
