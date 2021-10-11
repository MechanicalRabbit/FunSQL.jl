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

label(n::SQLNode) =
    label(n[])::Symbol

label(::Union{AbstractSQLNode, Nothing}) =
    :_

rebase(n::SQLNode, n′) =
    convert(SQLNode, rebase(n[], n′))


# Generic traversal and substitution.

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

visit(f, ::Nothing) =
    nothing

@generated function visit(f, n::AbstractSQLNode)
    exs = Expr[]
    for f in fieldnames(n)
        t = fieldtype(n, f)
        if t === SQLNode || t === Union{SQLNode, Nothing} || t === Vector{SQLNode}
            ex = quote
                visit(f, n.$(f))
            end
            push!(exs, ex)
        end
    end
    push!(exs, :(return nothing))
    Expr(:block, exs...)
end

substitute(n::SQLNode, c::SQLNode, c′::SQLNode) =
    SQLNode(substitute(n[], c, c′))

function substitute(ns::Vector{SQLNode}, c::SQLNode, c′::SQLNode)
    i = findfirst(isequal(c), ns)
    i !== nothing || return ns
    ns′ = copy(ns)
    ns′[i] = c′
    ns′
end

substitute(::Nothing, ::SQLNode, ::SQLNode) =
    nothing

@generated function substitute(n::AbstractSQLNode, c::SQLNode, c′::SQLNode)
    exs = Expr[]
    fs = fieldnames(n)
    for f in fs
        t = fieldtype(n, f)
        if t === SQLNode || t === Union{SQLNode, Nothing}
            ex = quote
                if n.$(f) === c
                    return $n($(Any[Expr(:kw, f′, f′ !== f ? :(n.$(f′)) : :(c′))
                                    for f′ in fs]...))
                end
            end
            push!(exs, ex)
        elseif t === Vector{SQLNode}
            ex = quote
                let cs′ = substitute(n.$(f), c, c′)
                    if cs′ !== n.$(f)
                        return $n($(Any[Expr(:kw, f′, f′ !== f ? :(n.$(f′)) : :(cs′))
                                        for f′ in fs]...))
                    end
                end
            end
            push!(exs, ex)
        end
    end
    push!(exs, :(return n))
    Expr(:block, exs...)
end


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


# Errors.

struct DuplicateAliasError <: FunSQLError
    name::Symbol
    path::Vector{SQLNode}

    DuplicateAliasError(name; path = SQLNode[]) =
        new(name, path)
end

function Base.showerror(io::IO, err::DuplicateAliasError)
    print(io, "DuplicateAliasError: $(err.name)")
    showpath(io, err.path)
end

struct IllFormedError <: FunSQLError
    path::Vector{SQLNode}

    IllFormedError(; path = SQLNode[]) =
        new(path)
end

function Base.showerror(io::IO, err::IllFormedError)
    print(io, "IllFormedError")
    showpath(io, err.path)
end

@enum ReferenceErrorType::UInt8 begin
    UNDEFINED_HANDLE
    AMBIGUOUS_HANDLE
    UNDEFINED_NAME
    AMBIGUOUS_NAME
    UNEXPECTED_ROW_TYPE
    UNEXPECTED_SCALAR_TYPE
    UNEXPECTED_AGGREGATE
    AMBIGUOUS_AGGREGATE
end

struct ReferenceError <: FunSQLError
    type::ReferenceErrorType
    name::Union{Symbol, Nothing}
    path::Vector{SQLNode}

    ReferenceError(type; name = nothing, path = SQLNode[]) =
        new(type, name, path)
end

function Base.showerror(io::IO, err::ReferenceError)
    print(io, "ReferenceError: $(err.type)")
    if err.name !== nothing
        print(io, " ($(err.name))")
    end
    showpath(io, err.path)
end

function showpath(io, path::Vector{SQLNode})
    if !isempty(path)
        q = highlight(path)
        println(io, " in:")
        pprint(io, q)
    end
end

function highlight(path::Vector{SQLNode}, color = Base.error_color())
    @assert !isempty(path)
    n = Highlight(over = path[1], color = color)
    for k = 2:lastindex(path)
        n = substitute(path[k], path[k-1], n)
    end
    n
end


# Concrete node types.

include("nodes/aggregate.jl")
include("nodes/append.jl")
include("nodes/as.jl")
include("nodes/bind.jl")
include("nodes/define.jl")
include("nodes/from.jl")
include("nodes/function.jl")
include("nodes/get.jl")
include("nodes/group.jl")
include("nodes/highlight.jl")
include("nodes/join.jl")
include("nodes/limit.jl")
include("nodes/literal.jl")
include("nodes/order.jl")
include("nodes/partition.jl")
include("nodes/select.jl")
include("nodes/sort.jl")
include("nodes/variable.jl")
include("nodes/where.jl")

