# Join node.

mutable struct JoinNode <: TabularNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    left::Bool
    right::Bool

    JoinNode(; over = nothing, joinee, on, left = false, right = false) =
        new(over, joinee, on, left, right)
end

JoinNode(joinee; over = nothing, on, left = false, right = false) =
    JoinNode(over = over, joinee = joinee, on = on, left = left, right = right)

JoinNode(joinee, on; over = nothing, left = false, right = false) =
    JoinNode(over = over, joinee = joinee, on = on, left = left, right = right)

"""
    Join(; over = nothing, joinee, on, left = false, right = false)
    Join(joinee; over = nothing, on, left = false, right = false)
    Join(joinee, on; over = nothing, left = false, right = false)

`Join` correlates two input datasets.

```sql
SELECT ...
FROM \$over
JOIN \$joinee ON \$on
```

# Examples

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
             joinee = n.joinee, on = n.on, left = n.left, right = n.right)

