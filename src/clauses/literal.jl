# Literal value.

mutable struct LiteralClause <: AbstractSQLClause
    val

    LiteralClause(; val) =
        new(val)
end

LiteralClause(val) =
    LiteralClause(; val)

"""
    LIT(; val)
    LIT(val)

A SQL literal.

In a context of a SQL clause, `missing`, numbers, strings and datetime values
are automatically converted to SQL literals.

# Examples

```jldoctest
julia> s = LIT(missing);

julia> print(render(s))
NULL
```

```jldoctest
julia> s = LIT("SQL is fun!");

julia> print(render(s))
'SQL is fun!'
```
"""
LIT = SQLSyntaxCtor{LiteralClause}

Base.convert(::Type{SQLSyntax}, val::SQLLiteralType) =
    LIT(val)

terminal(::Type{LiteralClause}) =
    true

PrettyPrinting.quoteof(c::LiteralClause, ::QuoteContext) =
    Expr(:call, :LIT, c.val)
