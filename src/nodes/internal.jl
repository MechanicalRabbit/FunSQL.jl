# Auxiliary nodes.

# Preserve context between rendering passes.
mutable struct WithContextNode <: AbstractSQLNode
    over::SQLNode
    dialect::SQLDialect
    tables::Dict{Symbol, SQLTable}
    defs::Vector{SQLNode}

    WithContextNode(; over, dialect = default_dialect, tables = Dict{Symbol, SQLTable}(), defs = SQLNode[]) =
        new(over, dialect, tables, defs)
end

WithContext(args...; kws...) =
    WithContextNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(WithContext), pats::Vector{Any}) =
    dissect(scr, WithContextNode, pats)

function PrettyPrinting.quoteof(n::WithContextNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(WithContext), Expr(:kw, :over, quoteof(n.over, ctx)))
    if n.dialect != default_dialect
        push!(ex.args, Expr(:kw, :dialect, quoteof(n.dialect)))
    end
    if !isempty(n.tables)
        push!(ex.args, Expr(:kw, :tables, quoteof(n.tables)))
    end
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

# A generic From node is specialized to FromNothing, FromTable,
# FromTableExpression, FromKnot, FromValues, or FromFunction.
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

mutable struct FromKnotNode <: TabularNode
end

FromKnot(args...; kws...) =
    FromKnotNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromKnotNode, ctx::QuoteContext) =
    Expr(:call, nameof(FromKnot))

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

mutable struct IntJoinNode <: TabularNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    router::JoinRouter
    left::Bool
    right::Bool
    lateral::Bool
    optional::Bool

    IntJoinNode(; over, joinee, on, router, left, right, lateral = false, optional = false) =
        new(over, joinee, on, router, left, right, lateral, optional)
end

IntJoinNode(joinee, on; over = nothing, router, left = false, right = false, lateral = false, optional = false) =
    IntJoinNode(over = over, joinee = joinee, on = on, router, left = left, right = right, lateral = lateral, optional = optional)

IntJoin(args...; kws...) =
    IntJoinNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::IntJoinNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(IntJoin))
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

# Calculates the keys of a Group node.
mutable struct IntAutoDefineNode <: TabularNode
    over::Union{SQLNode, Nothing}

    IntAutoDefineNode(; over = nothing) =
        new(over)
end

IntAutoDefine(args...; kws...) =
    IntAutoDefineNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::IntAutoDefineNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(IntAutoDefine))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

# Isolated subquery.
mutable struct IsolatedNode <: AbstractSQLNode
    idx::Int

    IsolatedNode(; idx) =
        new(idx)
end

IsolatedNode(idx) =
    IsolatedNode(idx = idx)

Isolated(args...; kws...) =
    IsolatedNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::IsolatedNode, ctx::QuoteContext) =
    Expr(:call, nameof(Isolated), n.idx)

dissect(scr::Symbol, ::typeof(Isolated), pats::Vector{Any}) =
    dissect(scr, IsolatedNode, pats)
