# HAVING clause.

mutable struct HavingClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    condition::SQLClause

    HavingClause(;
                 over = nothing,
                 condition) =
        new(over, condition)
end

HavingClause(condition; over = nothing) =
    HavingClause(over = over, condition = condition)

"""
    HAVING(; over = nothing, condition)
    HAVING(condition; over = nothing)

A `HAVING` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           GROUP(:year_of_birth) |>
           HAVING(OP(">", AGG("COUNT", OP("*")), 10)) |>
           SELECT(:person_id);

julia> print(render(c))
SELECT "person_id"
FROM "person"
GROUP BY "year_of_birth"
HAVING (COUNT(*) > 10)
```
"""
HAVING(args...; kws...) =
    HavingClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(HAVING), pats::Vector{Any}) =
    dissect(scr, HavingClause, pats)

function PrettyPrinting.quoteof(c::HavingClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(HAVING), quoteof(c.condition, qctx))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::HavingClause, c′) =
    HavingClause(over = rebase(c.over, c′), condition = c.condition)

