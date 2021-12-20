# Semantic structure of a SQL query.


# Base node type.

"""
A SQL expression.
"""
abstract type AbstractSQLNode
end

# A node that produces tabular output.
abstract type TabularNode <: AbstractSQLNode
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

function visit(f, n::SQLNode, visiting = Set{SQLNode}())
    !(n in visiting) || return
    push!(visiting, n)
    visit(f, n[], visiting)
    f(n)
    pop!(visiting, n)
    nothing
end

function visit(f, ns::Vector{SQLNode}, visiting)
    for n in ns
        visit(f, n, visiting)
    end
end

visit(f, ::Nothing, visiting) =
    nothing

@generated function visit(f, n::AbstractSQLNode, visiting)
    exs = Expr[]
    for f in fieldnames(n)
        t = fieldtype(n, f)
        if t === SQLNode || t === Union{SQLNode, Nothing} || t === Vector{SQLNode}
            ex = quote
                visit(f, n.$(f), visiting)
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

function PrettyPrinting.quoteof(n::SQLNode;
                                limit::Bool = false,
                                unwrap::Bool = false)
    if limit
        ctx = QuoteContext(limit = true)
        ex = quoteof(n[], ctx)
        if unwrap
            ex = Expr(:ref, ex)
        end
        return ex
    end
    tables_seen = OrderedSet{SQLTable}()
    nodes_seen = OrderedSet{SQLNode}()
    nodes_toplevel = Set{SQLNode}()
    visit(n) do n
        core = n[]
        if core isa FromNode
            source = core.source
            if source isa SQLTable
                push!(tables_seen, source)
            end
        end
        if core isa FromTableNode
            push!(tables_seen, core.table)
        end
        if core isa TabularNode
            push!(nodes_seen, n)
            push!(nodes_toplevel, n)
        elseif n in nodes_seen
            push!(nodes_toplevel, n)
        else
            push!(nodes_seen, n)
        end
    end
    ctx = QuoteContext()
    defs = Any[]
    if length(nodes_toplevel) >= 2 || (length(nodes_toplevel) == 1 && !(n in nodes_toplevel))
        for t in tables_seen
            def = quoteof(t, limit = true)
            name = t.name
            push!(defs, Expr(:(=), name, def))
            ctx.vars[t] = name
        end
        qidx = 0
        for n in nodes_seen
            n in nodes_toplevel || continue
            qidx += 1
            ctx.vars[n] = Symbol('q', qidx)
        end
        qidx = 0
        for n in nodes_seen
            n in nodes_toplevel || continue
            qidx += 1
            name = Symbol('q', qidx)
            def = quoteof(n, ctx, true)
            push!(defs, Expr(:(=), name, def))
        end
    end
    ex = quoteof(n, ctx)
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

PrettyPrinting.quoteof(n::SQLNode, ctx::QuoteContext, full::Bool = false) =
    if !ctx.limit
        !full || return quoteof(n[], ctx)
        var = get(ctx.vars, n, nothing)
        if var !== nothing
            var
        else
            quoteof(n[], ctx)
        end
    else
        :…
    end

PrettyPrinting.quoteof(ns::Vector{SQLNode}, ctx::QuoteContext) =
    if isempty(ns)
        Any[]
    elseif !ctx.limit
        Any[quoteof(n, ctx) for n in ns]
    else
        Any[:…]
    end


# Errors.

struct DuplicateLabelError <: FunSQLError
    name::Symbol
    path::Vector{SQLNode}

    DuplicateLabelError(name; path = SQLNode[]) =
        new(name, path)
end

function Base.showerror(io::IO, err::DuplicateLabelError)
    print(io, "FunSQL.DuplicateLabelError: $(err.name) is used more than once")
    showpath(io, err.path)
end

struct IllFormedError <: FunSQLError
    path::Vector{SQLNode}

    IllFormedError(; path = SQLNode[]) =
        new(path)
end

function Base.showerror(io::IO, err::IllFormedError)
    print(io, "FunSQL.IllFormedError")
    showpath(io, err.path)
end

module REFERENCE_ERROR_TYPE

@enum ReferenceErrorType::UInt8 begin
    UNDEFINED_HANDLE
    AMBIGUOUS_HANDLE
    UNDEFINED_NAME
    AMBIGUOUS_NAME
    UNEXPECTED_ROW_TYPE
    UNEXPECTED_SCALAR_TYPE
    UNEXPECTED_AGGREGATE
    AMBIGUOUS_AGGREGATE
    UNDEFINED_TABLE_REFERENCE
    INVALID_TABLE_REFERENCE
end

end

import .REFERENCE_ERROR_TYPE.ReferenceErrorType

struct ReferenceError <: FunSQLError
    type::ReferenceErrorType
    name::Union{Symbol, Nothing}
    path::Vector{SQLNode}

    ReferenceError(type; name = nothing, path = SQLNode[]) =
        new(type, name, path)
end

function Base.showerror(io::IO, err::ReferenceError)
    print(io, "FunSQL.ReferenceError: ")
    if err.type == REFERENCE_ERROR_TYPE.UNDEFINED_HANDLE
        print(io, "node-bound reference failed to resolve")
    elseif err.type == REFERENCE_ERROR_TYPE.AMBIGUOUS_HANDLE
        print(io, "node-bound reference is ambiguous")
    elseif err.type == REFERENCE_ERROR_TYPE.UNDEFINED_NAME
        print(io, "cannot find $(err.name)")
    elseif err.type == REFERENCE_ERROR_TYPE.AMBIGUOUS_NAME
        print(io, "$(err.name) is ambiguous")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE
        print(io, "incomplete reference $(err.name)")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE
        print(io, "unexpected reference after $(err.name)")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_AGGREGATE
        print(io, "aggregate expression requires Group or Partition")
    elseif err.type == REFERENCE_ERROR_TYPE.AMBIGUOUS_AGGREGATE
        print(io, "aggregate expression is ambiguous")
    elseif err.type == REFERENCE_ERROR_TYPE.UNDEFINED_TABLE_REFERENCE
        print(io, "cannot find $(err.name)")
    elseif err.type == REFERENCE_ERROR_TYPE.INVALID_TABLE_REFERENCE
        print(io, "table reference $(err.name) requires As")
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
include("nodes/iterate.jl")
include("nodes/join.jl")
include("nodes/limit.jl")
include("nodes/literal.jl")
include("nodes/order.jl")
include("nodes/partition.jl")
include("nodes/select.jl")
include("nodes/sort.jl")
include("nodes/variable.jl")
include("nodes/where.jl")
include("nodes/with.jl")

