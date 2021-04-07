# Where node.

mutable struct WhereNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    condition::SQLNode

    WhereNode(; over = nothing, condition) =
        new(over, condition)
end

WhereNode(condition; over = nothing) =
    WhereNode(over = over, condition = condition)

"""
    Where(; over = nothing, condition)
    Where(condition; over = nothing)

A subquery that filters by the given `condition`.

```sql
SELECT ... FROM \$over WHERE \$condition
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Where(Call(">", Get.year_of_birth, 2000));

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."year_of_birth" > 2000)
```
"""
Where(args...; kws...) =
    WhereNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::WhereNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Where), quoteof(n.condition, qctx))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::WhereNode, n′) =
    WhereNode(over = rebase(n.over, n′), condition = n.condition)

