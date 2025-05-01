# Sorting.

struct OrderNode <: TabularNode
    by::Vector{SQLQuery}

    OrderNode(; by) =
        new(by)
end

OrderNode(by...) =
    OrderNode(by = SQLQuery[by...])

"""
    Order(; by, tail = nothing)
    Order(by...; tail = nothing)

`Order` sorts the input rows `by` the given key.

The `Order `node is translated to a query with an `ORDER BY` clause:
```sql
SELECT ...
FROM \$over
ORDER BY \$by...
```

Specify the sort order with [`Asc`](@ref), [`Desc`](@ref), or [`Sort`](@ref).

# Examples

*List patients ordered by their age.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Order(Get.year_of_birth);

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth"
```
"""
const Order = SQLQueryCtor{OrderNode}(:Order)

const funsql_order = Order

function PrettyPrinting.quoteof(n::OrderNode, ctx::QuoteContext)
    ex = Expr(:call, :Order)
    if isempty(n.by)
        push!(ex.args, Expr(:kw, :by, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.by, ctx))
    end
    ex
end
