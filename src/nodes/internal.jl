# Auxiliary nodes.

# Preserve context between rendering passes.
mutable struct WithContextNode <: AbstractSQLNode
    over::SQLNode
    catalog::SQLCatalog
    defs::Vector{SQLNode}

    WithContextNode(; over, catalog = SQLCatalog(), defs = SQLNode[]) =
        new(over, catalog, defs)
end

WithContext(args...; kws...) =
    WithContextNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(WithContext), pats::Vector{Any}) =
    dissect(scr, WithContextNode, pats)

function PrettyPrinting.quoteof(n::WithContextNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(WithContext), Expr(:kw, :over, quoteof(n.over, ctx)))
    push!(ex.args, Expr(:kw, :catalog, quoteof(n.catalog)))
    if !isempty(n.defs)
        push!(ex.args, Expr(:kw, :defs, Expr(:vect, Any[quoteof(def, ctx) for def in n.defs]...)))
    end
    ex
end

# Annotations added by "resolve" pass.
mutable struct ResolvedNode <: AbstractSQLNode
    over::SQLNode
    type::AbstractSQLType

    ResolvedNode(; over, type) =
        new(over, type)
end

ResolvedNode(type; over) =
    ResolvedNode(over = over, type = type)

Resolved(args...; kws...) =
    ResolvedNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Resolved), pats::Vector{Any}) =
    dissect(scr, ResolvedNode, pats)

function PrettyPrinting.quoteof(n::ResolvedNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Resolved), quoteof(n.type))
    push!(ex.args, Expr(:kw, :over, quoteof(n.over, ctx)))
    ex
end

# Annotations added by "link" pass.
mutable struct LinkedNode <: TabularNode
    over::SQLNode
    refs::Vector{SQLNode}
    n_ext_refs::Int

    LinkedNode(; over, refs = SQLNode[], n_ext_refs = length(refs)) =
        new(over, refs, n_ext_refs)
end

LinkedNode(refs, n_ext_refs = length(refs); over) =
    LinkedNode(over = over, refs = refs, n_ext_refs = n_ext_refs)

Linked(args...; kws...) =
    LinkedNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Linked), pats::Vector{Any}) =
    dissect(scr, LinkedNode, pats)

function PrettyPrinting.quoteof(n::LinkedNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Linked))
    if !isempty(n.refs)
        push!(ex.args, Expr(:vect, Any[quoteof(ref, ctx) for ref in n.refs]...))
    end
    if n.n_ext_refs != length(n.refs)
        push!(ex.args, n.n_ext_refs)
    end
    push!(ex.args, Expr(:kw, :over, quoteof(n.over, ctx)))
    ex
end

# Get(over = Get(:a), name = :b) => Nested(over = Get(:b), name = :a)
mutable struct NestedNode <: AbstractSQLNode
    over::SQLNode
    name::Symbol

    NestedNode(; over, name) =
        new(over, name)
end

Nested(args...; kws...) =
    NestedNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Nested), pats::Vector{Any}) =
    dissect(scr, NestedNode, pats)

PrettyPrinting.quoteof(n::NestedNode, ctx::QuoteContext) =
    Expr(:call, nameof(Nested), Expr(:kw, :over, quoteof(n.over, ctx)), Expr(:kw, :name, QuoteNode(n.name)))

# Var() that found the corresponding Bind()
mutable struct BoundVariableNode <: AbstractSQLNode
    name::Symbol
    depth::Int

    BoundVariableNode(; name, depth) =
        new(name, depth)
end

BoundVariableNode(name, depth) =
    BoundVariableNode(name = name, depth = depth)

BoundVariable(args...; kws...) =
    BoundVariableNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::BoundVariableNode, ctx::QuoteContext) =
    Expr(:call, nameof(BoundVariable), QuoteNode(n.name), n.depth)

# A generic From node is specialized to FromNothing, FromTable,
# FromTableExpression, FromIterate, FromValues, or FromFunction.
mutable struct FromNothingNode <: TabularNode
end

FromNothing(args...; kws...) =
    FromNothingNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(::FromNothingNode, ::QuoteContext) =
    Expr(:call, nameof(FromNothing))

mutable struct FromTableNode <: TabularNode
    table::SQLTable

    FromTableNode(; table) =
        new(table)
end

FromTable(args...; kws...) =
    FromTableNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::FromTableNode, ctx::QuoteContext)
    tex = get(ctx.vars, n.table, nothing)
    if tex === nothing
        tex = quoteof(n.table, limit = true)
    end
    Expr(:call, nameof(FromTable), Expr(:kw, :table, tex))
end

mutable struct FromTableExpressionNode <: TabularNode
    name::Symbol
    depth::Int

    FromTableExpressionNode(; name, depth) =
        new(name, depth)
end

FromTableExpressionNode(name, depth) =
    FromTableExpressionNode(name = name, depth = depth)

FromTableExpression(args...; kws...) =
    FromTableExpressionNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromTableExpressionNode, ctx::QuoteContext) =
    Expr(:call, nameof(FromTableExpression), QuoteNode(n.name), n.depth)

mutable struct FromIterateNode <: TabularNode
end

FromIterate(args...; kws...) =
    FromIterateNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromIterateNode, ctx::QuoteContext) =
    Expr(:call, nameof(FromIterate))

mutable struct FromValuesNode <: TabularNode
    columns::NamedTuple

    FromValuesNode(; columns) =
        new(columns)
end

FromValues(args...; kws...) =
    FromValuesNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromValuesNode, ctx::QuoteContext) =
    Expr(:call, nameof(FromValues), Expr(:kw, :columns, quoteof(n.columns, ctx)))

mutable struct FromFunctionNode <: TabularNode
    over::SQLNode
    columns::Vector{Symbol}

    FromFunctionNode(; over, columns) =
        new(over, columns)
end

FromFunction(args...; kws...) =
    FromFunctionNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromFunctionNode, ctx::QuoteContext) =
    Expr(:call,
         nameof(FromFunction),
         Expr(:kw, :over, quoteof(n.over, ctx)),
         Expr(:kw, :columns, Expr(:vect, [QuoteNode(col) for col in n.columns]...)))

# Annotated Join node.
struct JoinRouter
    label_set::Set{Symbol}
    group::Bool
end

PrettyPrinting.quoteof(r::JoinRouter) =
    Expr(:call, nameof(JoinRouter), quoteof(r.label_set), quoteof(r.group))

mutable struct RoutedJoinNode <: TabularNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    router::JoinRouter
    left::Bool
    right::Bool
    lateral::Bool
    optional::Bool

    RoutedJoinNode(; over, joinee, on, router, left, right, lateral = false, optional = false) =
        new(over, joinee, on, router, left, right, lateral, optional)
end

RoutedJoinNode(joinee, on; over = nothing, router, left = false, right = false, lateral = false, optional = false) =
    RoutedJoinNode(over = over, joinee = joinee, on = on, router, left = left, right = right, lateral = lateral, optional = optional)

RoutedJoin(args...; kws...) =
    RoutedJoinNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::RoutedJoinNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(RoutedJoin))
    if !ctx.limit
        push!(ex.args, quoteof(n.joinee, ctx))
        push!(ex.args, quoteof(n.on, ctx))
        push!(ex.args, Expr(:kw, :router, quoteof(n.router)))
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
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

# Calculates the keys of a Group node.  Also used by Iterate.
mutable struct PaddingNode <: TabularNode
    over::Union{SQLNode, Nothing}

    PaddingNode(; over = nothing) =
        new(over)
end

Padding(args...; kws...) =
    PaddingNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::PaddingNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Padding))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

# Isolated subquery.
mutable struct IsolatedNode <: AbstractSQLNode
    idx::Int
    type::RowType

    IsolatedNode(; idx, type) =
        new(idx, type)
end

IsolatedNode(idx, type) =
    IsolatedNode(idx = idx, type = type)

Isolated(args...; kws...) =
    IsolatedNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::IsolatedNode, ctx::QuoteContext) =
    Expr(:call, nameof(Isolated), n.idx, quoteof(n.type))

dissect(scr::Symbol, ::typeof(Isolated), pats::Vector{Any}) =
    dissect(scr, IsolatedNode, pats)
