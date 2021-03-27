# FROM clause.

mutable struct FromClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    modifier::Union{SQLClause, Nothing}

    FromClause(; over = nothing, modifier = nothing) =
        new(over, modifier)
end

FromClause(over; modifier = nothing) =
    FromClause(over = over, modifier = modifier)

"""
    FROM(; over = nothing, modifier = nothing)
    FROM(over; modifier = nothing)

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
    if c.modifier !== nothing
        push!(ex.args, !limit ? Expr(:kw, :modifier, quoteof(c.modifier)) : :…)
    end
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

