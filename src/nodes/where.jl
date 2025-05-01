# Where node.

struct WhereNode <: TabularNode
    condition::SQLQuery

    WhereNode(; condition) =
        new(condition)
end

WhereNode(condition) =
    WhereNode(; condition)

"""
    Where(; condition, tail = nothing)
    Where(condition; tail = nothing)

The `Where` node filters the input rows by the given `condition`.

`Where` is translated to a SQL query with a `WHERE` clause:
```sql
SELECT ...
FROM \$over
WHERE \$condition
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Where(Fun(">", Get.year_of_birth, 2000));

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."year_of_birth" > 2000)
```
"""
const Where = SQLQueryCtor{WhereNode}(:Where)

const funsql_filter = Where

PrettyPrinting.quoteof(n::WhereNode, ctx::QuoteContext) =
    Expr(:call, :Where, quoteof(n.condition, ctx))
