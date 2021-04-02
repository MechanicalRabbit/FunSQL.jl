# Semantic structure of a SQL query.


# Base node type.

"""
A SQL operation.
"""
abstract type AbstractSQLNode
end

Base.show(io::IO, n::AbstractSQLNode) =
    print(io, quoteof(n, limit = true))

Base.show(io::IO, ::MIME"text/plain", n::AbstractSQLNode) =
    pprint(io, n)


# Specialization barrier node.

"""
An opaque wrapper over an arbitrary SQL node.
"""
struct SQLNode <: AbstractSQLNode
    content::AbstractSQLNode

    SQLNode(@nospecialize content::AbstractSQLNode) =
        new(content)
end

Base.getindex(n::SQLNode) =
    getfield(n, :content)

Base.convert(::Type{SQLNode}, n::SQLNode) =
    n

Base.convert(::Type{SQLNode}, @nospecialize n::AbstractSQLNode) =
    SQLNode(n)

Base.convert(::Type{SQLNode}, obj) =
    convert(SQLNode, convert(AbstractSQLNode, obj)::AbstractSQLNode)

PrettyPrinting.quoteof(n::SQLNode; limit::Bool = false, wrap::Bool = false) =
    quoteof(n[], limit = limit, wrap = true)

(n::AbstractSQLNode)(n′) =
    n(convert(SQLNode, n′))

(n::AbstractSQLNode)(n′::SQLNode) =
    rebase(n, n′)

rebase(n::SQLNode, n′) =
    convert(SQLNode, rebase(n[], n′))


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


# Concrete node types.

include("nodes/as.jl")
include("nodes/call.jl")
include("nodes/from.jl")
include("nodes/get.jl")
include("nodes/literal.jl")
include("nodes/select.jl")
include("nodes/where.jl")

