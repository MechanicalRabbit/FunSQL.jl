# Auxiliary nodes.

# Preserve context between rendering passes.
struct WithContextNode <: AbstractSQLNode
    catalog::SQLCatalog
    defs::Vector{SQLQuery}

    WithContextNode(; catalog = SQLCatalog(), defs = SQLQuery[]) =
        new(catalog, defs)
end

const WithContext = SQLQueryCtor{WithContextNode}(:WithContext)

function PrettyPrinting.quoteof(n::WithContextNode, ctx::QuoteContext)
    ex = Expr(:call, :WithContext)
    push!(ex.args, Expr(:kw, :catalog, quoteof(n.catalog)))
    if !isempty(n.defs)
        push!(ex.args, Expr(:kw, :defs, Expr(:vect, Any[quoteof(def, ctx) for def in n.defs]...)))
    end
    ex
end

# Annotations added by "resolve" pass.
struct ResolvedNode <: AbstractSQLNode
    type::AbstractSQLType

    ResolvedNode(; type) =
        new(type)
end

ResolvedNode(type) =
    ResolvedNode(type = type)

const Resolved = SQLQueryCtor{ResolvedNode}(:Resolved)

function PrettyPrinting.quoteof(n::ResolvedNode, ctx::QuoteContext)
    Expr(:call, :Resolved, quoteof(n.type))
end

# Annotations added by "link" pass.
struct LinkedNode <: AbstractSQLNode
    refs::Vector{SQLQuery}
    n_ext_refs::Int

    LinkedNode(; refs = SQLQuery[], n_ext_refs = length(refs)) =
        new(refs, n_ext_refs)
end

LinkedNode(refs, n_ext_refs = length(refs)) =
    LinkedNode(refs = refs, n_ext_refs = n_ext_refs)

const Linked = SQLQueryCtor{LinkedNode}(:Linked)

function PrettyPrinting.quoteof(n::LinkedNode, ctx::QuoteContext)
    ex = Expr(:call, :Linked)
    if !isempty(n.refs)
        push!(ex.args, Expr(:vect, Any[quoteof(ref, ctx) for ref in n.refs]...))
    end
    if n.n_ext_refs != length(n.refs)
        push!(ex.args, n.n_ext_refs)
    end
    ex
end

# @funsql(a.b) == Get(tail = Get(:a), name = :b) => Nested(tail = Get(:b), name = :a)
struct NestedNode <: AbstractSQLNode
    name::Symbol

    NestedNode(; name) =
        new(name)
end

NestedNode(name) =
    NestedNode(; name)

const Nested = SQLQueryCtor{NestedNode}(:Nested)

PrettyPrinting.quoteof(n::NestedNode, ctx::QuoteContext) =
    Expr(:call, :Nested, QuoteNode(n.name))


# Var() that found the corresponding Bind()
struct BoundVariableNode <: AbstractSQLNode
    name::Symbol
    depth::Int

    BoundVariableNode(; name, depth) =
        new(name, depth)
end

BoundVariableNode(name, depth) =
    BoundVariableNode(; name, depth)

const BoundVariable = SQLQueryCtor{BoundVariableNode}(:BoundVariable)

terminal(::Type{BoundVariableNode}) =
    true

PrettyPrinting.quoteof(n::BoundVariableNode, ctx::QuoteContext) =
    Expr(:call, :BoundVariable, QuoteNode(n.name), n.depth)


# A generic From node is specialized to FromNothing, FromTable,
# FromTableExpression, FromIterate, FromValues, or FromFunction.
struct FromNothingNode <: TabularNode
end

const FromNothing = SQLQueryCtor{FromNothingNode}(:FromNothing)

terminal(::Type{FromNothingNode}) =
    true

PrettyPrinting.quoteof(::FromNothingNode, ::QuoteContext) =
    Expr(:call, :FromNothing)

struct FromTableNode <: TabularNode
    table::SQLTable

    FromTableNode(; table) =
        new(table)
end

FromTableNode(table) =
    FromTableNode(; table)

const FromTable = SQLQueryCtor{FromTableNode}(:FromTable)

terminal(::Type{FromTableNode}) =
    true

function PrettyPrinting.quoteof(n::FromTableNode, ctx::QuoteContext)
    tex = get(ctx.repl, n.table, nothing)
    if tex === nothing
        tex = quoteof(n.table, limit = true)
    end
    Expr(:call, :FromTable, tex)
end

struct FromTableExpressionNode <: TabularNode
    name::Symbol
    depth::Int

    FromTableExpressionNode(; name, depth) =
        new(name, depth)
end

FromTableExpressionNode(name, depth) =
    FromTableExpressionNode(; name, depth)

const FromTableExpression = SQLQueryCtor{FromTableExpressionNode}(:FromTableExpression)

terminal(::Type{FromTableExpressionNode}) =
    true

PrettyPrinting.quoteof(n::FromTableExpressionNode, ctx::QuoteContext) =
    Expr(:call, :FromTableExpression, QuoteNode(n.name), n.depth)

struct FromIterateNode <: TabularNode
end

const FromIterate = SQLQueryCtor{FromIterateNode}(:FromIterate)

terminal(::Type{FromIterateNode}) =
    true

PrettyPrinting.quoteof(n::FromIterateNode, ctx::QuoteContext) =
    Expr(:call, :FromIterate)

struct FromValuesNode <: TabularNode
    columns::NamedTuple

    FromValuesNode(; columns) =
        new(columns)
end

FromValuesNode(columns) =
    FromValuesNode(; columns)

const FromValues = SQLQueryCtor{FromValuesNode}(:FromValues)

terminal(::Type{FromValuesNode}) =
    true

PrettyPrinting.quoteof(n::FromValuesNode, ctx::QuoteContext) =
    Expr(:call, :FromValues, quoteof(n.columns, ctx))

struct FromFunctionNode <: TabularNode
    columns::Vector{Symbol}

    FromFunctionNode(; columns) =
        new(columns)
end

FromFunctionNode(columns) =
    FromFunctionNode(; columns)

const FromFunction = SQLQueryCtor{FromFunctionNode}(:FromFunction)

PrettyPrinting.quoteof(n::FromFunctionNode, ctx::QuoteContext) =
    Expr(:call,
         :FromFunction,
         Expr(:vect, [QuoteNode(col) for col in n.columns]...))


# Annotated Join node.
struct RoutedJoinNode <: TabularNode
    joinee::SQLQuery
    on::SQLQuery
    name::Symbol
    left::Bool
    right::Bool
    lateral::Bool
    optional::Bool

    RoutedJoinNode(; joinee, on, name = label(joinee), left, right, lateral = false, optional = false) =
        new(joinee, on, name, left, right, lateral, optional)
end

RoutedJoinNode(joinee, on; name = label(joinee), left = false, right = false, lateral = false, optional = false) =
    RoutedJoinNode(name = name, on = on, router, left = left, right = right, lateral = lateral, optional = optional)

const RoutedJoin = SQLQueryCtor{RoutedJoinNode}(:RoutedJoin)

function PrettyPrinting.quoteof(n::RoutedJoinNode, ctx::QuoteContext)
    ex = Expr(:call, :RoutedJoin)
    if !ctx.limit
        push!(ex.args, quoteof(n.joinee, ctx))
        push!(ex.args, quoteof(n.on, ctx))
        push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
        if n.left
            push!(ex.args, Expr(:kw, :left, n.left))
        end
        if n.right
            push!(ex.args, Expr(:kw, :right, n.right))
        end
        if n.lateral
            push!(ex.args, Expr(:kw, :lateral, n.lateral))
        end
        if n.optional
            push!(ex.args, Expr(:kw, :optional, n.optional))
        end
    else
        push!(ex.args, :…)
    end
    ex
end


# Calculates the keys of a Group node.  Also used by Iterate.
struct PaddingNode <: TabularNode
end

const Padding = SQLQueryCtor{PaddingNode}(:Padding)

PrettyPrinting.quoteof(n::PaddingNode, ctx::QuoteContext) =
    Expr(:call, :Padding)


# Isolated subquery.
struct IsolatedNode <: AbstractSQLNode
    idx::Int
    type::RowType

    IsolatedNode(; idx, type) =
        new(idx, type)
end

IsolatedNode(idx, type) =
    IsolatedNode(; idx, type)

const Isolated = SQLQueryCtor{IsolatedNode}(:Isolated)

terminal(::Type{IsolatedNode}) =
    true

PrettyPrinting.quoteof(n::IsolatedNode, ctx::QuoteContext) =
    Expr(:call, :Isolated, n.idx, quoteof(n.type))


# Wraps a query generated with @funsql macro.
struct FunSQLMacroNode <: AbstractSQLNode
    query::SQLQuery
    ex
    mod::Module
    def::Union{Symbol, Nothing}
    base::LineNumberNode
    line::LineNumberNode

    FunSQLMacroNode(; query, ex, mod, def, base, line) =
        new(query, ex, mod, def, base, line)
end

FunSQLMacroNode(query, ex, mod, def, base, line) =
    FunSQLMacroNode(; query, ex, mod, def, base, line)

const FunSQLMacro = SQLQueryCtor{FunSQLMacroNode}(:FunSQLMacro)

terminal(n::FunSQLMacroNode) =
    terminal(n.query)

PrettyPrinting.quoteof(n::FunSQLMacroNode, ctx::QuoteContext) =
    Expr(:macrocall, Symbol("@funsql"), n.line, !ctx.limit ? n.ex : :…)

label(n::FunSQLMacroNode) =
    label(n.query, default = nothing)


# Unwrap @funsql macro when displaying the query.
struct UnwrapFunSQLMacroNode <: AbstractSQLNode
    depth::Union{Int}

    UnwrapFunSQLMacroNode(; depth = -1) =
        new(depth)
end

UnwrapFunSQLMacroNode(depth) =
    UnwrapFunSQLMacroNode(; depth)

const UnwrapFunSQLMacro = SQLQueryCtor{UnwrapFunSQLMacroNode}(:UnwrapFunSQLMacro)

function PrettyPrinting.quoteof(n::UnwrapFunSQLMacroNode, ctx::QuoteContext)
    ex = Expr(:call, :UnwrapFunSQLMacro)
    if n.depth != -1
        push!(ex.args, n.depth)
    end
    ex
end

unwrap_funsql_macro(q; depth = -1) =
    q |> UnwrapFunSQLMacro(depth)


# Highlight a target node for error reporting.
struct HighlightTargetNode <: AbstractSQLNode
    target::Any
    color::Symbol

    HighlightTargetNode(; target, color) =
        new(target, color)
end

HighlightTargetNode(target, color) =
    HighlightTargetNode(; target, color)

const HighlightTarget = SQLQueryCtor{HighlightTargetNode}(:HighlightTarget)

PrettyPrinting.quoteof(n::HighlightTargetNode, ctx::QuoteContext) =
    Expr(:call, :HighlightTarget, :…, QuoteNode(n.color))
