# Semantic structure of a SQL query.


# Base node type.

"""
A SQL operation.
"""
abstract type AbstractSQLNode
end

visit(f, @nospecialize n::AbstractSQLNode) =
    nothing

visit(f, ::Nothing) =
    nothing


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

function visit(f, n::SQLNode)
    visit(f, n[])
    f(n)
    nothing
end

function visit(f, ns::Vector{SQLNode})
    for n in ns
        visit(f, n)
    end
end


# Converting to SQL syntax.

struct ResolveContext
    dialect::SQLDialect
    aliases::Dict{Symbol, Int}

    ResolveContext(dialect) =
        new(dialect, Dict{Symbol, Int}())
end

struct ResolveRequest
    ctx::ResolveContext
    refs::Vector{SQLNode}
    top::Bool

    ResolveRequest(ctx; refs = SQLNode[], top = false) =
        new(ctx, refs, top)
end

struct ResolveResult
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
end

"""
    resolve(node; dialect = :default)

Convert the node to a SELECT clause.
"""
function resolve(n::SQLNode; dialect = :default)
    ctx = ResolveContext(dialect)
    req = ResolveRequest(ctx, refs = star(n), top = true)
    resolve(convert(SQLNode, n), req)
end

resolve(n; kws...) =
    resolve(convert(SQLNode, n); kws...)

function render(n; dialect = :default)
    res = resolve(n, dialect = dialect)
    render(res.clause, dialect = dialect)
end

function allocate_alias(ctx::ResolveContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

allocate_alias(ctx::ResolveContext, n) =
    allocate_alias(ctx, alias(n))

alias(n::SQLNode) =
    alias(n[])::Symbol

alias(::Nothing) =
    :_

star(n::SQLNode) =
    star(n[])::Vector{SQLNode}

star(n) =
    SQLNode[]

function gather!(refs::Vector{SQLNode}, n::SQLNode)
    gather!(refs, n[])
    refs
end

function gather!(refs::Vector{SQLNode}, ns::Vector{SQLNode})
    for n in ns
        gather!(refs, n)
    end
    refs
end

gather!(refs::Vector{SQLNode}, ::AbstractSQLNode) =
    refs

translate(n::SQLNode, subs) =
    n in keys(subs) ?
        subs[n] :
        convert(SQLClause, translate(n[], subs))

resolve(n::SQLNode, req) =
    resolve(n[], req)::ResolveResult

function resolve(::Nothing, req)
    c = SELECT(list = SQLClause[true])
    repl = Dict{SQLNode, Symbol}()
    ResolveResult(c, repl)
end


# Pretty-printing.

Base.show(io::IO, n::AbstractSQLNode) =
    print(io, quoteof(n, limit = true))

Base.show(io::IO, ::MIME"text/plain", n::AbstractSQLNode) =
    pprint(io, n)

struct SQLNodeQuoteContext
    limit::Bool
    vars::IdDict{Any, Symbol}

    SQLNodeQuoteContext(; limit = false, vars = IdDict{Any, Symbol}()) =
        new(limit, vars)
end



PrettyPrinting.quoteof(n::AbstractSQLNode; limit::Bool = false) =
    quoteof(SQLNode(n), limit = limit, unwrap = true)

function PrettyPrinting.quoteof(n::SQLNode; limit::Bool = false, unwrap::Bool = false)
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
        if core isa Union{FromNode, SelectNode, WhereNode}
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
include("nodes/call.jl")
include("nodes/from.jl")
include("nodes/get.jl")
include("nodes/literal.jl")
include("nodes/select.jl")
include("nodes/where.jl")

