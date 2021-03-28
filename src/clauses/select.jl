# SELECT clause.

mutable struct SelectClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    distinct::Bool
    list::Vector{SQLClause}

    SelectClause(;
                 over = nothing,
                 distinct = false,
                 list) =
        new(over, distinct, list)
end

SelectClause(list...; over = nothing, distinct = false) =
    SelectClause(over = over, distinct = distinct, list = SQLClause[list...])

"""
    SELECT(; over = nothing, distinct = false, list)
    SELECT(list...; over = nothing, distinct = false)

A `SELECT` clause.  Unlike raw SQL, `SELECT()` should be placed at the end of a
clause chain.

Set `distinct` to `true` to add a `DISTINCT` modifier.

# Examples

```julia-repl
julia> c = SELECT(true, false);

julia> print(render(c))
SELECT TRUE, FALSE
```

```julia-repl
julia> c = FROM(:location) |>
           SELECT(distinct = true, :zip);

julia> print(render(c))
SELECT DISTINCT zip
FROM location
```
"""
SELECT(args...; kws...) =
    SelectClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::SelectClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(SELECT) : nameof(SelectClause))
    if !limit
        if c.distinct !== false
            push!(ex.args, Expr(:kw, :distinct, c.distinct))
        end
        list_exs = Any[quoteof(item) for item in c.list]
        if isempty(c.list)
            push!(ex.args, Expr(:kw, :list, Expr(:vect, list_exs...)))
        else
            append!(ex.args, list_exs)
        end
    else
        push!(ex.args, :…)
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::SelectClause, c′) =
    SelectClause(over = rebase(c.over, c′), distinct = c.distinct, list = c.list)

function render(ctx, c::SelectClause)
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, '(')
        newline(ctx)
    end
    ctx.nested = true
    print(ctx, "SELECT")
    if c.distinct
        print(ctx, " DISTINCT")
    end
    if !isempty(c.list)
        render(ctx, c.list, left = " ", right = "")
    end
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ')')
    end
end

