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

`Iterate` outputs `over` concatenated with `iterator` recursively applied
to `over`.

```sql
WITH RECURSIVE iterate AS (
  SELECT ...
  FROM \$over
  UNION ALL
  SELECT ...
  FROM \$iterator
)
SELECT ...
FROM iterate
```

# Examples

```jldoctest
julia> q = Define(:n => 1, :p => 1, :q => 0) |>
           Iterate(
               From(:fib) |>
               Define(:n => Get.n .+ 1, :p => Get.p .+ Get.q, :q => Get.p) |>
               Where(Get.n .<= 10) |>
               As(:fib)) |>
           Select(Get.n, Get.p);

julia> print(render(q))
WITH RECURSIVE "fib_1" ("n", "p", "q") AS (
  SELECT
    1 AS "n",
    1 AS "p",
    0 AS "q"
  UNION ALL
  SELECT
    ("fib_1"."n" + 1) AS "n",
    ("fib_1"."p" + "fib_1"."q") AS "p",
    "fib_1"."p" AS "q"
  FROM "fib_1"
  WHERE (("fib_1"."n" + 1) <= 10)
)
SELECT
  "fib_1"."n",
  "fib_1"."p"
FROM "fib_1"
```

```jldoctest
julia> concept =
           SQLTable(:concept,
                    columns = [:concept_id, :concept_name]);

julia> concept_relationship =
           SQLTable(:concept_relationship,
                    columns = [:concept_id_1, :concept_id_2, :relationship_id]);

julia> SubtypesOf(base) =
           From(concept) |>
           Join(From(concept_relationship) |>
                Where(Get.relationship_id .== "Is a"),
                on = Get.concept_id .== Get.concept_id_1) |>
           Join(:base => base,
                on = Get.concept_id_2 .== Get.base.concept_id);

julia> q = From(concept) |>
           Where(Get.concept_id .== 4329847) |>
           Iterate(:subtype => SubtypesOf(From(:subtype)));

julia> print(render(q))
WITH RECURSIVE "subtype_1" ("concept_id", "concept_name") AS (
  SELECT
    "concept_1"."concept_id",
    "concept_1"."concept_name"
  FROM "concept" AS "concept_1"
  WHERE ("concept_1"."concept_id" = 4329847)
  UNION ALL
  SELECT
    "concept_2"."concept_id",
    "concept_2"."concept_name"
  FROM "concept" AS "concept_2"
  JOIN (
    SELECT
      "concept_relationship_1"."concept_id_1",
      "concept_relationship_1"."concept_id_2"
    FROM "concept_relationship" AS "concept_relationship_1"
    WHERE ("concept_relationship_1"."relationship_id" = 'Is a')
  ) AS "concept_relationship_2" ON ("concept_2"."concept_id" = "concept_relationship_2"."concept_id_1")
  JOIN "subtype_1" ON ("concept_relationship_2"."concept_id_2" = "subtype_1"."concept_id")
)
SELECT
  "subtype_1"."concept_id",
  "subtype_1"."concept_name"
FROM "subtype_1"
```
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

