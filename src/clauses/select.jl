# SELECT clause.

mutable struct SelectClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    distinct::Bool
    modifier::Union{SQLClause, Nothing}
    list::Vector{SQLClause}

    SelectClause(;
                 over = nothing,
                 distinct::Bool = false,
                 modifier = nothing,
                 list::AbstractVector) =
        new(over,
            distinct,
            modifier,
            !isa(list, Vector{SQLClause}) ?
                SQLClause[item for item in list] : list)
end

SelectClause(list...; over = nothing, distinct = false, modifier = nothing) =
    SelectClause(over = over, distinct = distinct, modifier = modifier, list = SQLClause[list...])

"""
    SELECT(; over = nothing, distinct = false, modifier = nothing, list)
    SELECT(list...; over = nothing, distinct = false, modifier = nothing)

A `SELECT` clause.

Set `distinct` to `true` to add a `DISTINCT` modifier.

# Examples

```julia-repl
julia> c = SELECT(true);

julia> print(render(c))
SELECT TRUE
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
        if c.modifier !== nothing
            push!(ex.args, Expr(:kw, :modifier, quoteof(c.modifier)))
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
    SelectClause(over = rebase(c.over, c′), distinct = c.distinct, modifier = c.modifier, list = c.list)

