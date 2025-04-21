# HAVING clause.

struct HavingClause <: AbstractSQLClause
    condition::SQLSyntax

    HavingClause(; condition) =
        new(condition)
end

HavingClause(condition) =
    HavingClause(; condition)

"""
    HAVING(; condition, tail = nothing)
    HAVING(condition, tail = nothing)

A `HAVING` clause.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           GROUP(:year_of_birth) |>
           HAVING(FUN(">", AGG(:count), 10)) |>
           SELECT(:person_id);

julia> print(render(s))
SELECT "person_id"
FROM "person"
GROUP BY "year_of_birth"
HAVING (count(*) > 10)
```
"""
const HAVING = SQLSyntaxCtor{HavingClause}

PrettyPrinting.quoteof(c::HavingClause, ctx::QuoteContext) =
    Expr(:call, :HAVING, quoteof(c.condition, ctx))
