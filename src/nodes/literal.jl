# Literal value.

mutable struct LiteralNode <: AbstractSQLNode
    val

    LiteralNode(; val) =
        new(val)
end

LiteralNode(val) =
    LiteralNode(val = val)

"""
    Lit(; val)
    Lit(val)

A SQL literal.

In a suitable context, `missing`, numbers, strings and datetime values are
automatically converted to SQL literals.

# Examples

```jldoctest
julia> q = Select(:null => missing,
                  :boolean => true,
                  :integer => 42,
                  :text => "SQL is fun!",
                  :date => Date(2000));

julia> print(render(q))
SELECT NULL AS "null", TRUE AS "boolean", 42 AS "integer", 'SQL is fun!' AS "text", '2000-01-01' AS "date"
```
"""
Lit(args...; kws...) =
    LiteralNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Lit), pats::Vector{Any}) =
    dissect(scr, LiteralNode, pats)

Base.convert(::Type{AbstractSQLNode}, val::SQLLiteralType) =
    LiteralNode(val)

Base.convert(::Type{AbstractSQLNode}, ref::Base.RefValue) =
    LiteralNode(ref.x)

PrettyPrinting.quoteof(n::LiteralNode, qctx::SQLNodeQuoteContext) =
    Expr(:call, nameof(Lit), n.val)

