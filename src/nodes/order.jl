# Sorting.

mutable struct OrderNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}
    offset::Union{Int, Nothing}
    limit::Union{Int, Nothing}

    OrderNode(; over = nothing, by, offset = nothing, limit = nothing) =
        new(over, by, offset, limit)
end

OrderNode(by...; over = nothing, offset = nothing, limit = nothing) =
    OrderNode(over = over, by = SQLNode[by...], offset = offset, limit = limit)

"""
    Order(; over; by = [], offset = nothing, limit = nothing)
    Order(by...; over, offset = nothing, limit = nothing)

A subquery that sorts the rows `by` a list of keys and, optionally, truncates
the dataset.

```sql
SELECT ...
FROM \$over
ORDER BY \$by...
OFFSET \$offset ROWS
FETCH NEXT \$limit ROWS ONLY
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Order(Get.year_of_birth) |>
           Select(Get.person_id);

julia> print(render(q))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth"
```
"""
Order(args...; kws...) =
    OrderNode(args...; kws...) |> SQLNode

Limit(; offset = nothing, limit = nothing, order_by = SQLNode[]) =
    Order(by = order_by, offset = offset, limit = limit)

Limit(limit; offset = nothing, order_by = SQLNode[]) =
    Limit(offset = offset, limit = limit, order_by = order_by)

Limit(offset, limit; order_by = SQLNode[]) =
    Limit(offset = offset, limit = limit, order_by = order_by)

Limit(range::UnitRange; order_by = SQLNode[]) =
    Limit(offset = first(range) - 1, limit = length(range), order_by = order_by)

dissect(scr::Symbol, ::typeof(Order), pats::Vector{Any}) =
    dissect(scr, OrderNode, pats)

function PrettyPrinting.quoteof(n::OrderNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Order))
    if isempty(n.by)
        push!(ex.args, Expr(:kw, :by, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.by, qctx))
    end
    if n.offset !== nothing
        push!(ex.args, Expr(:kw, :offset, n.offset))
    end
    if n.limit !== nothing
        push!(ex.args, Expr(:kw, :limit, n.limit))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::OrderNode, n′) =
    OrderNode(over = rebase(n.over, n′), by = n.by, offset = n.offset, limit = n.limit)

