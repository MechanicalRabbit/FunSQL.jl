# Truncating.

struct LimitNode <: TabularNode
    offset::Union{Int, Nothing}
    limit::Union{Int, Nothing}

    LimitNode(; offset = nothing, limit = nothing) =
        new(offset, limit)
end

LimitNode(limit; offset = nothing) =
    LimitNode(; offset, limit)

LimitNode(offset, limit) =
    LimitNode(; offset, limit)

LimitNode(range::UnitRange) =
    LimitNode(offset = first(range) - 1, limit = length(range))

"""
    Limit(; offset = nothing, limit = nothing, tail = nothing)
    Limit(limit; offset = nothing, tail = nothing)
    Limit(offset, limit; tail = nothing)
    Limit(start:stop; tail = nothing)

The `Limit` node skips the first `offset` rows and then emits the next `limit`
rows.

To make the output deterministic, `Limit` must be applied directly after
an [`Order`](@ref) node.

The `Limit` node is translated to a query with a `LIMIT` or a `FETCH` clause:
```sql
SELECT ...
FROM \$over
OFFSET \$offset ROWS
FETCH NEXT \$limit ROWS ONLY
```

# Examples

*Show the oldest patient.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Order(Get.year_of_birth) |>
           Limit(1);

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth"
FETCH FIRST 1 ROW ONLY
```
"""
const Limit = SQLQueryCtor{LimitNode}(:Limit)

const funsql_limit = Limit

function PrettyPrinting.quoteof(n::LimitNode, ctx::QuoteContext)
    ex = Expr(:call, :Limit)
    if n.offset !== nothing
        push!(ex.args, n.offset)
    end
    push!(ex.args, n.limit)
    ex
end
