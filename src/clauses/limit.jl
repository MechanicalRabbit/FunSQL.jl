# LIMIT clause.

struct LimitClause <: AbstractSQLClause
    offset::Union{Int, Nothing}
    limit::Union{Int, Nothing}
    with_ties::Bool

    LimitClause(;
                offset = nothing,
                limit = nothing,
                with_ties = false) =
        new(offset, limit, with_ties)
end

LimitClause(limit; offset = nothing, with_ties = false) =
    LimitClause(; offset, limit, with_ties = with_ties)

LimitClause(offset, limit; with_ties = false) =
    LimitClause(; offset, limit, with_ties)

LimitClause(range::UnitRange; with_ties = false) =
    LimitClause(; offset = first(range) - 1, limit = length(range), with_ties)

"""
    LIMIT(; offset = nothing, limit = nothing, with_ties = false, tail = nothing)
    LIMIT(limit; offset = nothing, with_ties = false, tail = nothing)
    LIMIT(offset, limit; with_ties = false, tail = nothing)
    LIMIT(start:stop; with_ties = false, tail = nothing)

A `LIMIT` clause.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           LIMIT(1) |>
           SELECT(:person_id);

julia> print(render(s))
SELECT "person_id"
FROM "person"
FETCH FIRST 1 ROW ONLY
```
"""
const LIMIT = SQLSyntaxCtor{LimitClause}

function PrettyPrinting.quoteof(c::LimitClause, ctx::QuoteContext)
    ex = Expr(:call, :LIMIT)
    if c.offset !== nothing
        push!(ex.args, c.offset)
    end
    push!(ex.args, c.limit)
    if c.with_ties
        push!(ex.args, Expr(:kw, :with_ties, c.with_ties))
    end
    ex
end
