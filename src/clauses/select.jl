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

```jldoctest
julia> c = SELECT(true, false);

julia> print(render(c))
SELECT TRUE, FALSE
```

```jldoctest
julia> c = FROM(:location) |>
           SELECT(distinct = true, :zip);

julia> print(render(c))
SELECT DISTINCT "zip"
FROM "location"
```
"""
SELECT(args...; kws...) =
    SelectClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(SELECT), pats::Vector{Any}) =
    dissect(scr, SelectClause, pats)

function PrettyPrinting.quoteof(c::SelectClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(SELECT))
    if c.distinct !== false
        push!(ex.args, Expr(:kw, :distinct, c.distinct))
    end
    if isempty(c.list)
        push!(ex.args, Expr(:kw, :list, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.list, qctx))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::SelectClause, c′) =
    SelectClause(over = rebase(c.over, c′), distinct = c.distinct, list = c.list)

