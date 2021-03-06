# Grouping.

mutable struct GroupNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}

    GroupNode(; over = nothing, by = SQLNode[]) =
        new(over, by)
end

GroupNode(by...; over = nothing) =
    GroupNode(over = over, by = SQLNode[by...])

"""
    Group(; over; by = [])
    Group(by...; over)

A subquery that groups rows `by` a list of keys.

```sql
SELECT ...
FROM \$over
GROUP BY \$by...
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group(Get.year_of_birth) |>
           Select(Get.year_of_birth, Agg.count());

julia> print(render(q))
SELECT "person_1"."year_of_birth", COUNT(*) AS "count"
FROM "person" AS "person_1"
GROUP BY "person_1"."year_of_birth"
```

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group() |>
           Select(Agg.count(distinct = true, Get.year_of_birth));

julia> print(render(q))
SELECT COUNT(DISTINCT "person_1"."year_of_birth") AS "count"
FROM "person" AS "person_1"
```
"""
Group(args...; kws...) =
    GroupNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Group), pats::Vector{Any}) =
    dissect(scr, GroupNode, pats)

function PrettyPrinting.quoteof(n::GroupNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Group), quoteof(n.by, qctx)...)
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::GroupNode, n′) =
    GroupNode(over = rebase(n.over, n′), by = n.by)

