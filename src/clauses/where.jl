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

```jldoctest
julia> c = FROM(:location) |>
           WHERE(OP("=", :zip, "60614")) |>
           SELECT(:location_id);

julia> print(render(c))
SELECT "location_id"
FROM "location"
WHERE ("zip" = '60614')
```
"""
WHERE(args...; kws...) =
    WhereClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::WhereClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(WHERE), quoteof(c.condition, qctx))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::WhereClause, c′) =
    WhereClause(over = rebase(c.over, c′), condition = c.condition)

function render(ctx, c::WhereClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    newline(ctx)
    print(ctx, "WHERE ")
    render(ctx, c.condition)
end

