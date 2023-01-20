# Semantic structure of a SQL query.


# Base node type.

"""
A tabular or a scalar operation that can be expressed as a SQL query.
"""
abstract type AbstractSQLNode
end

"""
A node that produces tabular output.
"""
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

Chain(n′, n) =
    rebase(convert(SQLNode, n), n′)


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
            def = quoteof(n, ctx, true, true)
            push!(defs, Expr(:(=), name, def))
        end
    end
    ex = quoteof(n, ctx, true, false)
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

PrettyPrinting.quoteof(n::SQLNode, ctx::QuoteContext, top::Bool = false, full::Bool = false) =
    if !ctx.limit
        !full || return quoteof(n[], ctx)
        var = get(ctx.vars, n, nothing)
        if var !== nothing
            var
        elseif !top && (local over = n[]; over isa LiteralNode) && (local val = over.val; val isa SQLLiteralType)
            quoteof(val)
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

"""
A duplicate label where unique labels are expected.
"""
struct DuplicateLabelError <: FunSQLError
    name::Symbol
    path::Vector{SQLNode}

    DuplicateLabelError(name; path = SQLNode[]) =
        new(name, path)
end

function Base.showerror(io::IO, err::DuplicateLabelError)
    print(io, "FunSQL.DuplicateLabelError: `", err.name, "` is used more than once")
    showpath(io, err.path)
end

"""
Unexpected number of arguments.
"""
struct InvalidArityError <: FunSQLError
    name::Symbol
    expected::Union{Int, UnitRange{Int}}
    actual::Int
    path::Vector{SQLNode}

    InvalidArityError(name, expected, actual; path = SQLNode[]) =
        new(name, expected, actual, path)
end

function Base.showerror(io::IO, err::InvalidArityError)
    print(io, "FunSQL.InvalidArityError: `", err.name, "` expects")
    expected = err.expected
    if expected isa Int
        plural = expected != 1
        print(io, " at least ", expected, " argument", plural ? "s" : "")
    else
        plural = last(expected) != 1
        if length(expected) == 1
            print(io, " ", first(expected), " argument", plural ? "s" : "")
        else
            print(io, " from ", first(expected), " to ", last(expected),
                  " argument", plural ? "s" : "")
        end
    end
    print(io, ", got ", err.actual)
    showpath(io, err.path)
end

function checkarity!(n)
    expected = arity(n.name)
    actual = length(n.args)
    if !(expected isa Int ? actual >= expected : actual in expected)
        throw(InvalidArityError(n.name, expected, actual, path = SQLNode[n]))
    end
end

"""
A scalar operation where a tabular operation is expected.
"""
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
    INVALID_SELF_REFERENCE
end

end

import .REFERENCE_ERROR_TYPE.ReferenceErrorType

"""
An undefined or an invalid reference.
"""
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
        print(io, "cannot find `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.AMBIGUOUS_NAME
        print(io, "`$(err.name)` is ambiguous")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE
        print(io, "incomplete reference `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE
        print(io, "unexpected reference after `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_AGGREGATE
        print(io, "aggregate expression requires Group or Partition")
    elseif err.type == REFERENCE_ERROR_TYPE.AMBIGUOUS_AGGREGATE
        print(io, "aggregate expression is ambiguous")
    elseif err.type == REFERENCE_ERROR_TYPE.UNDEFINED_TABLE_REFERENCE
        print(io, "cannot find `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.INVALID_TABLE_REFERENCE
        print(io, "table reference `$(err.name)` requires As")
    elseif err.type == REFERENCE_ERROR_TYPE.INVALID_SELF_REFERENCE
        print(io, "self-reference outside of Iterate")
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

"""
Invalid application of the [`@funsql`](@ref) macro.
"""
struct TransliterationError <: FunSQLError
    expr::Any
    src::LineNumberNode
end

function Base.showerror(io::IO, err::TransliterationError)
    println(io, "FunSQL.TransliterationError: ill-formed @funsql notation:")
    pprint(io, err.expr)
end

# Validate uniqueness of labels and cache arg->label map for Select.args and others.

function populate_label_map!(n, args = n.args, label_map = n.label_map, group_name = nothing)
    for (i, arg) in enumerate(args)
        name = label(arg)
        if name === group_name || name in keys(label_map)
            err = DuplicateLabelError(name, path = [arg, n])
            throw(err)
        end
        label_map[name] = i
    end
    n
end


# The @funsql macro.

struct TransliterateContext
    mod::Module
    src::LineNumberNode
    decl::Bool
    locals::Set{Symbol}

    TransliterateContext(mod::Module, src::LineNumberNode, decl::Bool = false, locals::Set{Symbol} = Set{Symbol}()) =
        new(mod, src, decl, locals)

    TransliterateContext(ctx::TransliterateContext; src = missing, decl = missing, locals = missing) =
        new(ctx.mod, coalesce(src, ctx.src), coalesce(decl, ctx.decl), coalesce(locals, ctx.locals))
end

"""
Convenient notation for assembling FunSQL queries.
"""
macro funsql(ex)
    transliterate(ex, TransliterateContext(__module__, __source__))
end

function transliterate(@nospecialize(ex), ctx::TransliterateContext)
    if ex isa Union{AbstractSQLNode, SQLLiteralType, Nothing}
        return ex
    elseif ex isa Symbol
        if ctx.decl
            push!(ctx.locals, ex)
            return esc(ex)
        elseif ex in ctx.locals
            return esc(ex)
        elseif ex in (:Inf, :NaN, :missing, :nothing)
            return GlobalRef(Base, ex)
        else
            return QuoteNode(ex)
        end
    elseif @dissect(ex, QuoteNode(name::Symbol))
        # :name
        return :(Var($ex))
    elseif ex isa Expr
        if @dissect(ex, Expr(:($), arg))
            # $(...)
            return esc(arg)
        elseif @dissect(ex, Expr(:(=), Expr(:call, name::Symbol, args...), body))
            # name(args...) = body
            ctx = TransliterateContext(ctx, decl = true, locals = Set{Symbol}())
            trs = _transliterate_params(:(::Val{$(QuoteNode(name))}), args, ctx)
            ctx = TransliterateContext(ctx, decl = false)
            return Expr(:(=),
                        :($(GlobalRef(FunSQL, :funsql))($(trs...))),
                        transliterate(body, ctx))
        elseif @dissect(ex, Expr(:(=), name::Symbol, arg))
            # name = arg
            return Expr(:(=), esc(name), transliterate(arg, ctx))
        elseif @dissect(ex, Expr(:kw, name::Symbol, arg))
            if ctx.decl
                push!(ctx.locals, name)
                ctx = TransliterateContext(ctx, decl = false)
            end
            return Expr(:kw, esc(name), transliterate(arg, ctx))
        elseif @dissect(ex, Expr(:(...), arg))
            # arg...
            return Expr(:(...), transliterate(arg, ctx))
        elseif @dissect(ex, Expr(:parameters, args...))
            # ; args...
            return Expr(:parameters, Any[transliterate(arg, ctx) for arg in args]...)
        elseif @dissect(ex, Expr(op := :const || :global || :local, arg))
            return Expr(op, transliterate(arg, ctx))
        elseif @dissect(ex, Cmd(name))
            # `name`
            return QuoteNode(Symbol(name))
        elseif @dissect(ex, Expr(:call, Expr(:., over, QuoteNode(name)), args...))
            # over.name(args...)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:call, name, args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:macrocall, Expr(:., over, Expr(:quote, ex′)), args...))
            # over.`name`(args...)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:macrocall, ex′, args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:ref, Expr(:., over, QuoteNode(name)), args...))
            # over.name[args...]
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:ref, name, args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:ref, Expr(:macrocall, Expr(:., over, Expr(:quote, ex′)), args′...), args...))
            # over.`name`[args...]
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:ref, Expr(:macrocall, ex′, args′...), args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:., over, QuoteNode(name)))
            # over.name
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(name, ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:call, :(=>), name := QuoteNode(_::Symbol), arg))
            # :name => arg
            tr = transliterate(arg, ctx)
            return :($name => $tr)
        elseif @dissect(ex, Expr(:call, :(=>), name, arg))
            # name => arg
            tr1 = transliterate(name, ctx)
            tr2 = transliterate(arg, ctx)
            return :($tr1 => $tr2)
        elseif @dissect(ex, Expr(:call, :(:), arg1, arg2))
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg2, ctx)
            return :($tr1:$tr2)
        elseif @dissect(ex, Expr(:vect, args...))
            # [args...]
            return Expr(:vect, Any[transliterate(arg, ctx) for arg in args]...)
        elseif @dissect(ex, Expr(:tuple, args...))
            # (args...)
            return Expr(:tuple, Any[transliterate(arg, ctx) for arg in args]...)
        elseif @dissect(ex, Expr(:comparison, arg1, arg2::Symbol, arg3))
            # Chained comparison.
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg3, ctx)
            return :(Fun($(QuoteNode(arg2)), $tr1, $tr2))
        elseif @dissect(ex, Expr(:comparison, arg1, arg2::Symbol, arg3, args...))
            # Chained comparison.
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg3, ctx)
            tr3 = transliterate(Expr(:comparison, arg3, args...), ctx)
            return :(Fun(:and, Fun($(QuoteNode(arg2)), $tr1, $tr2), $tr3))
        elseif @dissect(ex, Expr(:(&&), args...))
            # &&(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :(Fun(:and, args = [$(trs...)]))
        elseif @dissect(ex, Expr(:(||), args...))
            # ||(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :(Fun(:or, args = [$(trs...)]))
        elseif @dissect(ex, Expr(:call, op := :+ || :-, arg := :Inf))
            # ±Inf
            tr = transliterate(arg, ctx)
            return Expr(:call, op, tr)
        elseif @dissect(ex, Expr(:call, name::Symbol, args...))
            # name(args...)
            trs = _transliterate_params(:(Val($(QuoteNode(name)))), args, ctx)
            return :(funsql($(trs...)))
        elseif @dissect(ex, Expr(:call, Cmd(name), args...))
            # `name`(args...)
            trs = _transliterate_params(:(Val($(QuoteNode(Symbol(name))))), args, ctx)
            return :(funsql($(trs...)))
        elseif @dissect(ex, Expr(:ref, name::Symbol, args...))
            # name[args...]
            trs = _transliterate_params(QuoteNode(name), args, ctx)
            return :(Agg($(trs...)))
        elseif @dissect(ex, Expr(:ref, Cmd(name), args...))
            # `name`[args...]
            trs = _transliterate_params(QuoteNode(Symbol(name)), args, ctx)
            return :(Agg($(trs...)))
        elseif @dissect(ex, Expr(:let, Expr(:(=), name::Symbol, arg), over))
            # let name = arg; over; end
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(arg, ctx)
            tr3 = transliterate(name, ctx)
            return :(Chain($tr1, With(Chain($tr2, As($tr3)))))
        elseif @dissect(ex, Expr(:let, Expr(:block, arg), over))
            # let ... end
            return transliterate(Expr(:let, arg, over), ctx)
        elseif @dissect(ex, Expr(:let, Expr(:block, args..., arg), over))
            # let ... end
            return transliterate(Expr(:let, Expr(:block, args...), Expr(:let, arg, over)), ctx)
        elseif @dissect(ex, Expr(:block, args...))
            # begin; args...; end
            if all(arg isa LineNumberNode ||
                   @dissect(arg, Expr(:(=) || :const || :global || :local, _...))
                   for arg in args)
                trs = Any[]
                for arg in args
                    if arg isa LineNumberNode
                        ctx = TransliterateContext(ctx, src = arg)
                        push!(trs, arg)
                    else
                        push!(trs, transliterate(arg, ctx))
                    end
                end
                return Expr(:block, trs...)
            else
                tr = nothing
                for arg in args
                    if arg isa LineNumberNode
                        ctx = TransliterateContext(ctx, src = arg)
                    else
                        tr′ = Expr(:block, ctx.src, transliterate(arg, ctx))
                        tr = tr !== nothing ? :(Chain($tr, $tr′)) : tr′
                    end
                end
                return tr
            end
        elseif @dissect(ex, Expr(:if, arg1, arg2))
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg2, ctx)
            return :(Fun(:case, $tr1, $tr2))
        elseif @dissect(ex, Expr(:if, arg1, arg2, arg3))
            trs = Any[transliterate(arg1, ctx),
                      transliterate(arg2, ctx)]
            while @dissect(arg3, Expr(:if || :elseif, arg1′, arg2′, arg3′))
                push!(trs,
                      transliterate(arg1′, ctx),
                      transliterate(arg2′, ctx))
                arg3 = arg3′
            end
            if @dissect(arg3, Expr(:if || :elseif, arg1′, arg2′))
                push!(trs,
                      transliterate(arg1′, ctx),
                      transliterate(arg2′, ctx))
            else
                push!(trs, transliterate(arg3, ctx))
            end
            return :(Fun(:case, $(trs...)))
        end
    end
    throw(TransliterationError(ex, ctx.src))
end

function _transliterate_params(@nospecialize(tag), args, ctx)
    trs = Any[transliterate(arg, ctx) for arg in args]
    if !isempty(trs) && @dissect(trs[1], Expr(:parameters, _...))
        insert!(trs, 2, tag)
    else
        pushfirst!(trs, tag)
    end
    trs
end

funsql(@nospecialize(tag::Val{N}), args...; kws...) where {N} =
    Fun(N, args...; kws...)


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
include("nodes/with_external.jl")
