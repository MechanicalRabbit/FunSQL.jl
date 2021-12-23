# SELECT clause.

struct SelectTop
    limit::Int
    with_ties::Bool

    SelectTop(; limit, with_ties = false) =
        new(limit, with_ties)
end

Base.convert(::Type{SelectTop}, limit::Integer) =
    SelectTop(limit = limit)

Base.convert(::Type{SelectTop}, t::NamedTuple) =
    SelectTop(; t...)

function PrettyPrinting.quoteof(t::SelectTop)
    if !t.with_ties
        t.limit
    else
        Expr(:tuple, Expr(:(=), :limit, t.limit),
                     Expr(:(=), :with_ties, t.with_ties))
    end
end

mutable struct SelectClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    top::Union{SelectTop, Nothing}
    distinct::Bool
    args::Vector{SQLClause}

    SelectClause(;
                 over = nothing,
                 top = nothing,
                 distinct = false,
                 args) =
        new(over, top, distinct, args)
end

SelectClause(args...; over = nothing, top = nothing, distinct = false) =
    SelectClause(over = over, top = top, distinct = distinct, args = SQLClause[args...])

"""
    SELECT(; over = nothing, top = nothing, distinct = false, args)
    SELECT(args...; over = nothing, top = nothing, distinct = false)

A `SELECT` clause.  Unlike raw SQL, `SELECT()` should be placed at the end of a
clause chain.

Set `distinct` to `true` to add a `DISTINCT` modifier.

# Examples

```jldoctest
julia> c = SELECT(true, false);

julia> print(render(c))
SELECT
  TRUE,
  FALSE
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

function PrettyPrinting.quoteof(c::SelectClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(SELECT))
    if c.top !== nothing
        push!(ex.args, Expr(:kw, :top, quoteof(c.top)))
    end
    if c.distinct !== false
        push!(ex.args, Expr(:kw, :distinct, c.distinct))
    end
    if isempty(c.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.args, ctx))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::SelectClause, c′) =
    SelectClause(over = rebase(c.over, c′), top = c.top, distinct = c.distinct, args = c.args)

