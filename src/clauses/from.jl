# FROM clause.

mutable struct FromClause <: AbstractSQLClause
end

"""
    FROM(; tail = nothing)
    FROM(source)

A `FROM` clause.

# Examples

```jldoctest
julia> s = ID(:person) |> AS(:p) |> FROM() |> SELECT((:p, :person_id));

julia> print(render(s))
SELECT "p"."person_id"
FROM "person" AS "p"
```
"""
const FROM = SQLSyntaxCtor{FromClause}

FROM(source) =
    FROM(tail = source)

PrettyPrinting.quoteof(c::FromClause, ctx::QuoteContext) =
    Expr(:call, :FROM)
