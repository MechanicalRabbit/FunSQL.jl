# Semantic structure of a SQL query.


# Base node type.

"""
A SQL expression.
"""
abstract type AbstractSQLNode
end

abstract type SubqueryNode <: AbstractSQLNode
end

function dissect(scr::Symbol, NodeType::Type{<:AbstractSQLNode}, pats::Vector{Any})
    scr_core = gensym(:scr_core)
    ex = Expr(:&&, :($scr_core isa $NodeType), Any[dissect(scr_core, pat) for pat in pats]...)
    :($scr isa SQLNode && (local $scr_core = $scr[]; $ex))
end


# Specialization barrier node.

"""
An opaque wrapper over an arbitrary SQL node.
"""
struct SQLNode <: AbstractSQLNode
    core::AbstractSQLNode

    SQLNode(@nospecialize core::AbstractSQLNode) =
        new(core)
end

Base.getindex(n::SQLNode) =
    getfield(n, :core)

Base.convert(::Type{SQLNode}, n::SQLNode) =
    n

Base.convert(::Type{SQLNode}, @nospecialize n::AbstractSQLNode) =
    SQLNode(n)

Base.convert(::Type{SQLNode}, obj) =
    convert(SQLNode, convert(AbstractSQLNode, obj)::AbstractSQLNode)

(n::AbstractSQLNode)(n′) =
    n(convert(SQLNode, n′))

(n::AbstractSQLNode)(n′::SQLNode) =
    rebase(n, n′)

rebase(n::SQLNode, n′) =
    convert(SQLNode, rebase(n[], n′))


# Pretty-printing.

Base.show(io::IO, n::AbstractSQLNode) =
    print(io, quoteof(n, limit = true))

Base.show(io::IO, ::MIME"text/plain", n::AbstractSQLNode) =
    pprint(io, n)

struct SQLNodeQuoteContext
    limit::Bool
    vars::IdDict{Any, Symbol}
    colors::Vector{Symbol}

    SQLNodeQuoteContext(;
                        limit = false,
                        vars = IdDict{Any, Symbol}(),
                        colors = [:normal]) =
        new(limit, vars, colors)
end

function PrettyPrinting.quoteof(n::SQLNode;
                                limit::Bool = false,
                                unwrap::Bool = false)
    if limit
        qctx = SQLNodeQuoteContext(limit = true)
        ex = quoteof(n[], qctx)
        if unwrap
            ex = Expr(:ref, ex)
        end
        return ex
    end
    tables_ordered = SQLTable[]
    tables_seen = Set{SQLTable}()
    queries_ordered = SQLNode[]
    queries_seen = Set{SQLNode}()
    visit(n) do n
        core = n[]
        if core isa FromNode
            if !(core.table in tables_seen)
                push!(tables_ordered, core.table)
                push!(tables_seen, core.table)
            end
        end
        if core isa SubqueryNode
            if !(n in queries_seen)
                push!(queries_ordered, n)
                push!(queries_seen, n)
            end
        end
    end
    qctx = SQLNodeQuoteContext()
    defs = Any[]
    if length(queries_ordered) >= 2 || (length(queries_ordered) == 1 && queries_ordered[1] !== n)
        for t in tables_ordered
            def = quoteof(t, limit = true)
            name = t.name
            push!(defs, Expr(:(=), name, def))
            qctx.vars[t] = name
        end
        qidx = 0
        for n in queries_ordered
            def = quoteof(n, qctx)
            qidx += 1
            name = Symbol('q', qidx)
            push!(defs, Expr(:(=), name, def))
            qctx.vars[n] = name
        end
    end
    ex = quoteof(n, qctx)
    if unwrap
        ex = Expr(:ref, ex)
    end
    if !isempty(defs)
        ex = Expr(:let, Expr(:block, defs...), ex)
    end
    ex
end

PrettyPrinting.quoteof(n::AbstractSQLNode; limit::Bool = false) =
    quoteof(convert(SQLNode, n), limit = limit, unwrap = true)

PrettyPrinting.quoteof(n::SQLNode, qctx::SQLNodeQuoteContext) =
    if !qctx.limit
        var = get(qctx.vars, n, nothing)
        if var !== nothing
            var
        else
            quoteof(n[], qctx)
        end
    else
        :…
    end

PrettyPrinting.quoteof(ns::Vector{SQLNode}, qctx::SQLNodeQuoteContext) =
    if isempty(ns)
        Any[]
    elseif !qctx.limit
        Any[quoteof(n, qctx) for n in ns]
    else
        Any[:…]
    end


# Concrete node types.

include("nodes/as.jl")
include("nodes/from.jl")
include("nodes/function.jl")
include("nodes/get.jl")
include("nodes/highlight.jl")
include("nodes/literal.jl")
include("nodes/select.jl")
include("nodes/where.jl")

