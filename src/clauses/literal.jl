# Literal value.

mutable struct LiteralClause <: AbstractSQLClause
    val

    LiteralClause(; val) =
        new(val)
end

LiteralClause(val) =
    LiteralClause(val = val)

"""
    LIT(; val)
    LIT(val)

A SQL literal.

In a context of a SQL clause, `missing`, numbers, strings and datetime values
are automatically converted to SQL literals.

# Examples

```jldoctest
julia> c = LIT(missing);

julia> print(render(c))
NULL
```

```jldoctest
julia> c = LIT("SQL is fun!");

julia> print(render(c))
'SQL is fun!'
```
"""
LIT(args...; kws...) =
    LiteralClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(LIT), pats::Vector{Any}) =
    dissect(scr, LiteralClause, pats)

Base.convert(::Type{AbstractSQLClause}, val::SQLLiteralType) =
    LiteralClause(val)

PrettyPrinting.quoteof(c::LiteralClause, ::QuoteContext) =
    Expr(:call, nameof(LIT), c.val)

