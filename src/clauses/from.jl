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

```julia-repl
julia> c = ID(:person) |> AS(:p) |> FROM();

julia> print(render(c))
FROM "person" AS "p"
```
"""
FROM(args...; kws...) =
    FromClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::FromClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(FROM) : nameof(FromClause))
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::FromClause, c′) =
    FromClause(over = rebase(c.over, c′))

function render(ctx, c::FromClause)
    newline(ctx)
    print(ctx, "FROM")
    over = c.over
    if over !== nothing
        print(ctx, ' ')
        render(ctx, over)
    end
end

