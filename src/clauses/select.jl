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

struct SelectClause <: AbstractSQLClause
    top::Union{SelectTop, Nothing}
    distinct::Bool
    args::Vector{SQLSyntax}

    SelectClause(;
                 top = nothing,
                 distinct = false,
                 args) =
        new(top, distinct, args)
end

SelectClause(args...; top = nothing, distinct = false) =
    SelectClause(; top, distinct, args = SQLSyntax[args...])

"""
    SELECT(; top = nothing, distinct = false, args, tail = nothing)
    SELECT(args...; top = nothing, distinct = false, tail = nothing)

A `SELECT` clause.  Unlike raw SQL, `SELECT()` should be placed at the end of a
clause chain.

Set `distinct` to `true` to add a `DISTINCT` modifier.

# Examples

```jldoctest
julia> s = SELECT(true, false);

julia> print(render(s))
SELECT
  TRUE,
  FALSE
```

```jldoctest
julia> s = FROM(:location) |>
           SELECT(distinct = true, :zip);

julia> print(render(s))
SELECT DISTINCT "zip"
FROM "location"
```
"""
const SELECT = SQLSyntaxCtor{SelectClause}(:SELECT)

function PrettyPrinting.quoteof(c::SelectClause, ctx::QuoteContext)
    ex = Expr(:call, :SELECT)
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
    ex
end
