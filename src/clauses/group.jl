# GROUP BY clause.

mutable struct GroupClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    by::Vector{SQLClause}

    GroupClause(;
                over = nothing,
                by = SQLClause[]) =
        new(over, by)
end

GroupClause(by...; over = nothing) =
    GroupClause(over = over, by = SQLClause[by...])

"""
    GROUP(; over = nothing, by = [])
    GROUP(by...; over = nothing)

A `GROUP BY` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           GROUP(:year_of_birth) |>
           SELECT(:year_of_birth, AGG("COUNT", OP("*")));

julia> print(render(c))
SELECT "year_of_birth", COUNT(*)
FROM "person"
GROUP BY "year_of_birth"
```
"""
GROUP(args...; kws...) =
    GroupClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(GROUP), pats::Vector{Any}) =
    dissect(scr, GroupClause, pats)

function PrettyPrinting.quoteof(c::GroupClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(GROUP))
    append!(ex.args, quoteof(c.by, ctx))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::GroupClause, c′) =
    GroupClause(over = rebase(c.over, c′), by = c.by)

