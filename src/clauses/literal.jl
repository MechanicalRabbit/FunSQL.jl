# Literal value.

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

mutable struct LiteralClause <: AbstractSQLClause
    val
end

"""
    LITERAL(val)

A SQL literal.

In a context of a SQL clause, `missing`, numbers, strings and datetime values
are automatically converted to SQL literals.

# Examples

```julia-repl
julia> c = LITERAL(missing);

julia> print(render(c))
NULL
```

```julia-repl
julia> c = LITERAL("SQL is fun!");

julia> print(render(c))
'SQL is fun!'
```
"""
LITERAL(val) =
    LiteralClause(val) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, val::SQLLiteralType) =
    LiteralClause(val)

PrettyPrinting.quoteof(c::LiteralClause; limit::Bool = false, wrap::Bool = false) =
    Expr(:call, wrap ? nameof(LITERAL) : nameof(LiteralClause), c.val)

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

