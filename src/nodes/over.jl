# Over node.

struct OverNode <: TabularNode
    arg::SQLQuery
    materialized::Union{Bool, Nothing}

    OverNode(; arg, materialized = nothing) =
        new(arg, materialized)
end

OverNode(arg; materialized = nothing) =
    OverNode(arg = arg, materialized = materialized)

"""
    Over(; arg, materialized = nothing, tail = nothing)
    Over(arg; materialized = nothing, tail = nothing)

`base |> Over(arg)` is an alias for `With(base, tail = arg)`.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> condition_occurrence =
           SQLTable(:condition_occurrence, columns = [:condition_occurrence_id,
                                                      :person_id,
                                                      :condition_concept_id]);

julia> q = From(:condition_occurrence) |>
           Where(Get.condition_concept_id .== 320128) |>
           As(:essential_hypertension) |>
           Over(From(:person) |>
                Where(Fun.in(Get.person_id, From(:essential_hypertension) |>
                                            Select(Get.person_id))));

julia> print(render(q, tables = [person, condition_occurrence]))
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
  SELECT "essential_hypertension_2"."person_id"
  FROM "essential_hypertension_1" AS "essential_hypertension_2"
))
```
"""
const Over = SQLQueryCtor{OverNode}(:Over)

const funsql_over = Over

function PrettyPrinting.quoteof(n::OverNode, ctx::QuoteContext)
    ex = Expr(:call, :Over, quoteof(n.arg, ctx))
    if n.materialized !== nothing
        push!(ex.args, Expr(:kw, :materialized, n.materialized))
    end
    ex
end

label(n::OverNode) =
    label(n.arg)
