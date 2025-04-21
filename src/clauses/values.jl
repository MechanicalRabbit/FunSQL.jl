# VALUES clause.

struct ValuesClause <: AbstractSQLClause
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
julia> s = VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)]);

julia> print(render(s))
VALUES
  ('SQL', 1974),
  ('Julia', 2012),
  ('FunSQL', 2021)
```
"""
VALUES = SQLSyntaxCtor{ValuesClause}

terminal(::Type{ValuesClause}) =
    true

PrettyPrinting.quoteof(c::ValuesClause, ::QuoteContext) =
    Expr(:call, :VALUES, c.rows)
