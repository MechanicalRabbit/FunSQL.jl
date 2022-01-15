# Join node.

mutable struct JoinNode <: TabularNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    left::Bool
    right::Bool
    optional::Bool

    JoinNode(; over = nothing, joinee, on, left = false, right = false, optional = false) =
        new(over, joinee, on, left, right, optional)
end

JoinNode(joinee; over = nothing, on, left = false, right = false, optional = false) =
    JoinNode(over = over, joinee = joinee, on = on, left = left, right = right, optional = optional)

JoinNode(joinee, on; over = nothing, left = false, right = false, optional = false) =
    JoinNode(over = over, joinee = joinee, on = on, left = left, right = right, optional = optional)

"""
    Join(; over = nothing, joinee, on, left = false, right = false, optional = false)
    Join(joinee; over = nothing, on, left = false, right = false, optional = false)
    Join(joinee, on; over = nothing, left = false, right = false, optional = false)

`Join` correlates two input datasets.

The `Join` node is translated to a query with a `JOIN` clause:
```sql
SELECT ...
FROM \$over
JOIN \$joinee ON \$on
```

You can specify the join type:

* `INNER JOIN` (the default);
* `LEFT JOIN` (`left = true` or [`LeftJoin`](@ref));
* `RIGHT JOIN` (`right = true`);
* `FULL JOIN` (both `left = true` and `right = true`);
* `CROSS JOIN` (`on = true`).

When `optional` is set, the `JOIN` clause is omitted if the query does not
depend on any columns from the `joinee` branch.

To make a lateral join, apply [`Bind`](@ref) to the `joinee` branch.

Use [`As`](@ref) to disambiguate output columns.

# Examples

*Show patients with their state of residence.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :location_id]);

julia> location = SQLTable(:location, columns = [:location_id, :state]);

julia> q = person |>
           Join(:location => location,
                Get.location_id .== Get.location.location_id) |>
           Select(Get.person_id, Get.location.state);

julia> print(render(q))
SELECT
  "person_1"."person_id",
  "location_1"."state"
FROM "person" AS "person_1"
JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
```
"""
Join(args...; kws...) =
    JoinNode(args...; kws...) |> SQLNode

"""
An alias for `Join(...; ..., left = true)`.
"""
LeftJoin(args...; kws...) =
    Join(args...; kws..., left = true)

dissect(scr::Symbol, ::typeof(Join), pats::Vector{Any}) =
    dissect(scr, JoinNode, pats)

function PrettyPrinting.quoteof(n::JoinNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Join))
    if !ctx.limit
        push!(ex.args, quoteof(n.joinee, ctx))
        push!(ex.args, quoteof(n.on, ctx))
        if n.left
            push!(ex.args, Expr(:kw, :left, n.left))
        end
        if n.right
            push!(ex.args, Expr(:kw, :right, n.right))
        end
        if n.optional
            push!(ex.args, Expr(:kw, :optional, n.optional))
        end
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::JoinNode) =
    label(n.over)

rebase(n::JoinNode, n′) =
    JoinNode(over = rebase(n.over, n′),
             joinee = n.joinee, on = n.on, left = n.left, right = n.right, optional = n.optional)

