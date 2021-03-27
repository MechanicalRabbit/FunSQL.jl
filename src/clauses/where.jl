# WHERE clause.

mutable struct WhereClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    condition::SQLClause

    WhereClause(;
                 over = nothing,
                 condition) =
        new(over, condition)
end

WhereClause(condition; over = nothing) =
    WhereClause(over = over, condition = condition)

"""
    WHERE(; over = nothing, condition)
    WHERE(condition; over = nothing)

A `WHERE` clause.

# Examples

```julia-repl
julia> c = FROM(:location) |>
           WHERE(OP("=", :zip, "60614")) |>
           SELECT(:location_id);

julia> print(render(c))
SELECT "location_id"
FROM "location"
WHERE "zip" = '60614'
```
"""
WHERE(args...; kws...) =
    WhereClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::WhereClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call,
              wrap ? nameof(WHERE) : nameof(WhereClause),
              !limit ? quoteof(c.condition) : :…)
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::WhereClause, c′) =
    WhereClause(over = rebase(c.over, c′), condition = c.condition)

