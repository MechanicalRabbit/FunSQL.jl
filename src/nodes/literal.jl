# Literal value.

mutable struct LiteralNode <: AbstractSQLNode
    val

    LiteralNode(; val) =
        new(val)
end

LiteralNode(val) =
    LiteralNode(; val)

"""
    Lit(; val)
    Lit(val)

A SQL literal.

In a context where a SQL node is expected, `missing`, numbers, strings,
and datetime values are automatically converted to SQL literals.

# Examples

```jldoctest
julia> q = Select(:null => missing,
                  :boolean => true,
                  :integer => 42,
                  :text => "SQL is fun!",
                  :date => Date(2000));

julia> print(render(q))
SELECT
  NULL AS "null",
  TRUE AS "boolean",
  42 AS "integer",
  'SQL is fun!' AS "text",
  '2000-01-01' AS "date"
```
"""
const Lit = SQLQueryCtor{LiteralNode}(:Lit)

Base.convert(::Type{SQLQuery}, val::SQLLiteralType) =
    Lit(val)

Base.convert(::Type{SQLQuery}, ref::Base.RefValue) =
    Lit(ref.x)

terminal(::Type{LiteralNode}) =
    true

PrettyPrinting.quoteof(n::LiteralNode, ctx::QuoteContext) =
    Expr(:call, :Lit, n.val)
