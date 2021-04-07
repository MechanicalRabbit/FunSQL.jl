# FROM clause.

mutable struct FromClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}

    FromClause(; over = nothing) =
        new(over)
end

FromClause(over) =
    FromClause(over = over)

"""
    FROM(; over = nothing)
    FROM(over)

A `FROM` clause.

# Examples

```jldoctest
julia> c = ID(:person) |> AS(:p) |> FROM() |> SELECT((:p, :person_id));

julia> print(render(c))
SELECT "p"."person_id"
FROM "person" AS "p"
```
"""
FROM(args...; kws...) =
    FromClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(FROM), pats::Vector{Any}) =
    dissect(scr, FromClause, pats)

function PrettyPrinting.quoteof(c::FromClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(FROM))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::FromClause, c′) =
    FromClause(over = rebase(c.over, c′))

