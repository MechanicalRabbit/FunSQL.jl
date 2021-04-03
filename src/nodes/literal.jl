# Literal value.

mutable struct LiteralNode <: AbstractSQLNode
    val
end

"""
    Literal(val)

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
FROM (
  SELECT TRUE
) AS "__1"
```
"""
Literal(val) =
    LiteralNode(val) |> SQLNode

Base.convert(::Type{AbstractSQLNode}, val::SQLLiteralType) =
    LiteralNode(val)

PrettyPrinting.quoteof(n::LiteralNode; limit::Bool = false, wrap::Bool = false) =
    Expr(:call, wrap ? nameof(Literal) : nameof(LiteralNode), n.val)

alias(n::LiteralNode) =
    :_

translate(n::LiteralNode, subs) =
    LiteralClause(n.val)

