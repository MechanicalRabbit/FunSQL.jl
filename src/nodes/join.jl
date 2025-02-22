# Join node.

mutable struct JoinNode <: TabularNode
    joinee::SQLQuery
    on::SQLQuery
    left::Bool
    right::Bool
    optional::Bool
    swap::Bool

    JoinNode(; joinee, on, left = false, right = false, optional = false, swap = false) =
        new(joinee, on, left, right, optional, swap)
end

JoinNode(joinee; on, left = false, right = false, optional = false, swap = false) =
    JoinNode(; joinee, on, left, right, optional, swap)

JoinNode(joinee, on; left = false, right = false, optional = false, swap = false) =
    JoinNode(; joinee, on, left, right, optional, swap)

"""
    Join(; joinee, on, left = false, right = false, optional = false, swap = false)
    Join(joinee; on, left = false, right = false, optional = false, swap = false)
    Join(joinee, on; left = false, right = false, optional = false, swap = false)

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

julia> q = From(:person) |>
           Join(:location => From(:location),
                Get.location_id .== Get.location.location_id) |>
           Select(Get.person_id, Get.location.state);

julia> print(render(q, tables = [person, location]))
SELECT
  "person_1"."person_id",
  "location_1"."state"
FROM "person" AS "person_1"
JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
```
    """
const Join = SQLQueryCtor{JoinNode}(:Join)

"""
An alias for `Join(...; ..., left = true)`.
"""
LeftJoin(args...; kws...) =
    Join(args...; kws..., left = true)

"""
An alias for `Join(...; ..., on = true)`.
"""
CrossJoin(args...; kws...) =
    Join(args...; kws..., on = true)

const funsql_join = Join

const funsql_left_join = LeftJoin

const funsql_cross_join = CrossJoin

function PrettyPrinting.quoteof(n::JoinNode, ctx::QuoteContext)
    ex = Expr(:call, :Join)
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
        if n.swap
            push!(ex.args, Expr(:kw, :swap, n.swap))
        end
    else
        push!(ex.args, :…)
    end
    ex
end

label(n::JoinNode) =
    n.swap ? label(n.joinee) : label(n.over)
