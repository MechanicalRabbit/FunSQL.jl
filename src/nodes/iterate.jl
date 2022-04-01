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

`Iterate` generates the concatenated output of an iterated query.

The `over` query is evaluated first.  Then the `iterator` query is repeatedly
applied: to the output of `over`, then to the output of its previous run, and
so on, until the iterator produces no data.  All these outputs are concatenated
to generate the output of `Iterate`.

The `iterator` query should have an alias specified with [`As`](@ref); it can
refer to the output of the previous iteration using [`From`](@ref) with the same
alias.

The `Iterate` node is translated to a recursive common table expression:
```sql
WITH RECURSIVE iterator AS (
  SELECT ...
  FROM \$over
  UNION ALL
  SELECT ...
  FROM \$iterator
)
SELECT ...
FROM iterator
```

# Examples

*Calculate the factorial.*

```jldoctest
julia> q = Define(:n => 1, :f => 1) |>
           Iterate(
               From(:factorial) |>
               Define(:n => Get.n .+ 1) |>
               Define(:f => Get.f .* Get.n) |>
               Where(Get.n .<= 10) |>
               As(:factorial));

julia> print(render(q))
WITH RECURSIVE "factorial_1" ("n", "f") AS (
  SELECT
    1 AS "n",
    1 AS "f"
  UNION ALL
  SELECT
    ("factorial_2"."n" + 1) AS "n",
    ("factorial_2"."f" * ("factorial_2"."n" + 1)) AS "f"
  FROM "factorial_1" AS "factorial_2"
  WHERE (("factorial_2"."n" + 1) <= 10)
)
SELECT
  "factorial_3"."n",
  "factorial_3"."f"
FROM "factorial_1" AS "factorial_3"
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

