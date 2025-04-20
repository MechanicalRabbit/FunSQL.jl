# ORDER BY clause.

mutable struct OrderClause <: AbstractSQLClause
    by::Vector{SQLSyntax}

    OrderClause(; by = SQLSyntax[]) =
        new(by)
end

OrderClause(by...) =
    OrderClause(by = SQLSyntax[by...])

"""
    ORDER(; by = [], tail = nothing)
    ORDER(by...; tail = nothing)

An `ORDER BY` clause.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           ORDER(:year_of_birth) |>
           SELECT(:person_id);

julia> print(render(s))
SELECT "person_id"
FROM "person"
ORDER BY "year_of_birth"
```
"""
const ORDER = SQLSyntaxCtor{OrderClause}

function PrettyPrinting.quoteof(c::OrderClause, ctx::QuoteContext)
    ex = Expr(:call, :ORDER)
    append!(ex.args, quoteof(c.by, ctx))
    ex
end
