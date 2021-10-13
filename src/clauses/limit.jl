# LIMIT clause.

mutable struct LimitClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    offset::Union{Int, Nothing}
    limit::Union{Int, Nothing}
    with_ties::Bool

    LimitClause(;
                over = nothing,
                offset = nothing,
                limit = nothing,
                with_ties = false) =
        new(over, offset, limit, with_ties)
end

LimitClause(limit; over = nothing, offset = nothing, with_ties = false) =
    LimitClause(over = over, offset = offset, limit = limit, with_ties = with_ties)

LimitClause(offset, limit; over = nothing, with_ties = false) =
    LimitClause(over = over, offset = offset, limit = limit, with_ties = with_ties)

LimitClause(range::UnitRange, over = nothing, with_ties = false) =
    LimitClause(over = over, offset = first(range) - 1, limit = length(range), with_ties = with_ties)

"""
    LIMIT(; over = nothing, offset = nothing, limit = nothing, with_ties = false)
    LIMIT(limit; over = nothing, offset = nothing, with_ties = false)
    LIMIT(offset, limit; over = nothing, with_ties = false)
    LIMIT(start:stop; over = nothing, with_ties = false)

A `LIMIT` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           LIMIT(1) |>
           SELECT(:person_id);

julia> print(render(c))
SELECT "person_id"
FROM "person"
FETCH FIRST 1 ROW ONLY
```
"""
LIMIT(args...; kws...) =
    LimitClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(LIMIT), pats::Vector{Any}) =
    dissect(scr, LimitClause, pats)

function PrettyPrinting.quoteof(c::LimitClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(LIMIT))
    if c.offset !== nothing
        push!(ex.args, c.offset)
    end
    push!(ex.args, c.limit)
    if c.with_ties
        push!(ex.args, Expr(:kw, :with_ties, c.with_ties))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::LimitClause, c′) =
    LimitClause(over = rebase(c.over, c′), offset = c.offset, limit = c.limit, with_ties = c.with_ties)

