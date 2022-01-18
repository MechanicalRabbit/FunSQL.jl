# VALUES clause.

mutable struct ValuesClause <: AbstractSQLClause
    rows::Vector

    ValuesClause(; rows) =
        new(rows)
end

ValuesClause(rows) =
    ValuesClause(rows = rows)

"""
    VALUES(; rows)
    VALUES(rows)

A `VALUES` clause.

# Examples

```jldoctest
julia> c = VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)]);

julia> print(render(c))
VALUES
  ('SQL', 1974),
  ('Julia', 2012),
  ('FunSQL', 2021)
```
"""
VALUES(args...; kws...) =
    ValuesClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(VALUES), pats::Vector{Any}) =
    dissect(scr, ValuesClause, pats)

PrettyPrinting.quoteof(c::ValuesClause, ::QuoteContext) =
    Expr(:call, nameof(VALUES), c.rows)

