# Literal value.

mutable struct LiteralClause <: AbstractSQLClause
    val
end

"""
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
LIT(val) =
    LiteralClause(val) |> SQLClause

dissect(scr::Symbol, ::typeof(LIT), pats::Vector{Any}) =
    dissect(scr, LiteralClause, pats)

Base.convert(::Type{AbstractSQLClause}, val::SQLLiteralType) =
    LiteralClause(val)

PrettyPrinting.quoteof(c::LiteralClause, ::SQLClauseQuoteContext) =
    Expr(:call, nameof(LIT), c.val)

render(ctx, c::LiteralClause) =
    render(ctx, c.val)

render(ctx, ::Missing) =
    print(ctx, "NULL")

render(ctx, val::Bool) =
    print(ctx, val ? "TRUE" : "FALSE")

render(ctx, val::Number) =
    print(ctx, val)

render(ctx, val::AbstractString) =
    print(ctx, '\'', replace(val, '\'' => "''"), '\'')

render(ctx, val::Dates.Date) =
    print(ctx, '\'', val, '\'')

