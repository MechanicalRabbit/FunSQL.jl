# WHERE clause.

mutable struct WhereClause <: AbstractSQLClause
    condition::SQLSyntax

    WhereClause(; condition) =
        new(condition)
end

WhereClause(condition) =
    WhereClause(; condition)

"""
    WHERE(; condition, tail = nothing)
    WHERE(condition; tail = nothing)

A `WHERE` clause.

# Examples

```jldoctest
julia> s = FROM(:location) |>
           WHERE(FUN("=", :zip, "60614")) |>
           SELECT(:location_id);

julia> print(render(s))
SELECT "location_id"
FROM "location"
WHERE ("zip" = '60614')
```
"""
const WHERE = SQLSyntaxCtor{WhereClause}

PrettyPrinting.quoteof(c::WhereClause, ctx::QuoteContext) =
    Expr(:call, :WHERE, quoteof(c.condition, ctx))
