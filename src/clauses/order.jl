# ORDER BY clause.

mutable struct OrderClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    by::Vector{SQLClause}

    OrderClause(;
                over = nothing,
                by = SQLClause[]) =
        new(over, by)
end

OrderClause(by...; over = nothing) =
    OrderClause(over = over, by = SQLClause[by...])

"""
    ORDER(; over = nothing, by = [])
    ORDER(by...; over = nothing)

A `ORDER BY` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           ORDER(:year_of_birth) |>
           SELECT(:person_id);

julia> print(render(c))
SELECT "person_id"
FROM "person"
ORDER BY "year_of_birth"
```
"""
ORDER(args...; kws...) =
    OrderClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(ORDER), pats::Vector{Any}) =
    dissect(scr, OrderClause, pats)

function PrettyPrinting.quoteof(c::OrderClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(ORDER))
    append!(ex.args, quoteof(c.by, ctx))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::OrderClause, c′) =
    OrderClause(over = rebase(c.over, c′), by = c.by)

