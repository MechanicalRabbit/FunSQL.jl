# Literal value.

mutable struct LiteralNode <: AbstractSQLNode
    val
end

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

