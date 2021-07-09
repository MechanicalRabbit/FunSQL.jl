# Truncating.

mutable struct LimitNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    offset::Union{Int, Nothing}
    limit::Union{Int, Nothing}

    LimitNode(; over = nothing, offset = nothing, limit = nothing) =
        new(over, offset, limit)
end

LimitNode(limit; over = nothing, offset = nothing) =
    LimitNode(over = over, offset = offset, limit = limit)

LimitNode(offset, limit; over = nothing) =
    LimitNode(over = over, offset = offset, limit = limit)

LimitNode(range::UnitRange; over = nothing) =
    LimitNode(over = over, offset = first(range) - 1, limit = length(range))

"""
    Limit(; over = nothing, offset = nothing, limit = nothing)
    Limit(limit; over = nothing, offset = nothing)
    Limit(offset, limit; over = nothing)
    Limit(start:stop; over = nothing)

A subquery that takes a fixed-sized slice of the dataset.

```sql
SELECT ...
FROM \$over
OFFSET \$offset ROWS
FETCH NEXT \$limit ROWS ONLY
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id]);

julia> q = From(person) |>
           Limit(1) |>
           Select(Get.person_id);

julia> print(render(q))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
FETCH FIRST 1 ROW ONLY
```
"""
Limit(args...; kws...) =
    LimitNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Limit), pats::Vector{Any}) =
    dissect(scr, LimitNode, pats)

function PrettyPrinting.quoteof(n::LimitNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Limit))
    if n.offset !== nothing
        push!(ex.args, n.offset)
    end
    push!(ex.args, n.limit)
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::LimitNode, n′) =
    LimitNode(over = rebase(n.over, n′), offset = n.offset, limit = n.limit)

