# Semantic structure of a SQL query.


# Base node type.

"""
A component of a SQL query tree.
"""
abstract type AbstractSQLNode
end

terminal(::Type{<:AbstractSQLNode}) =
    false

terminal(n::N) where {N <: AbstractSQLNode} =
    terminal(N)

"""
A node that produces tabular output.
"""
abstract type TabularNode <: AbstractSQLNode
end


# Opaque linked list of SQL nodes.

"""
SQL query represented as a linked list of SQL nodes.
"""
mutable struct SQLQuery
    const tail::Union{SQLQuery, Nothing}
    const head::AbstractSQLNode

    SQLQuery(@nospecialize head::AbstractSQLNode) =
        new(nothing, head)

    function SQLQuery(tail, head::AbstractSQLNode)
        if tail !== nothing && terminal(head)
            throw(RebaseError(path = [SQLQuery(head)]))
        end
        new(tail, head)
    end
end

Base.convert(::Type{SQLQuery}, @nospecialize n::AbstractSQLNode) =
    SQLQuery(n)

terminal(q::SQLQuery) =
    q.tail !== nothing ? terminal(q.tail) : terminal(q.head)

(q::SQLQuery)(q′) =
    SQLQuery(q.tail !== nothing ? q.tail(q′) : q′, q.head)

Chain(q′, q) =
    convert(SQLQuery, q)(q′)

label(q::SQLQuery) =
    @something label(q.head) label(q.tail)

label(n::AbstractSQLNode) =
    nothing

label(::Nothing) =
    :_

label(q) =
    label(convert(SQLQuery, q))


# A variant of SQLQuery for assembling a chain of identifiers.

struct SQLGetQuery
    tail::Union{SQLGetQuery, Nothing}
    head::Symbol
end

Base.getproperty(q::SQLGetQuery, name::Symbol) =
    SQLGetQuery(q, Symbol(name))

Base.getproperty(q::SQLGetQuery, name::AbstractString) =
    SQLGetQuery(q, Symbol(name))

Base.getindex(q::SQLGetQuery, name::Union{Symbol, AbstractString}) =
    SQLGetQuery(q, Symbol(name))

(q::SQLGetQuery)(::Nothing) =
    q

(q::SQLGetQuery)(q′::SQLGetQuery) =
    let head = getfield(q, :head), tail = getfield(q, :tail)
        SQLGetQuery(tail !== nothing ? tail(q′) : q′, head)
    end

(q::SQLGetQuery)(q′) =
    convert(SQLQuery, q)(q′)

Base.show(io::IO, q::SQLGetQuery) =
    print(io, quoteof(q))

function PrettyPrinting.quoteof(q::SQLGetQuery)
    path = Symbol[]
    while q !== nothing
        push!(path, getfield(q, :head))
        q = getfield(q, :tail)
    end
    ex = :Get
    while !isempty(path)
        ex = Expr(:., ex, QuoteNode(pop!(path)))
    end
    ex
end

function _tosqlgetquery(q)
    q.head isa GetNode || return
    tail′ = nothing
    if q.tail !== nothing
        tail′ = _tosqlgetquery(q.tail)
        tail′ !== nothing || return
    end
    SQLGetQuery(tail′, q.head.name)
end


# Generic traversal and substitution.

function visit(f, q::SQLQuery, visiting = Set{SQLQuery}())
    !(q in visiting) || return
    push!(visiting, q)
    visit(f, q.tail, visiting)
    visit(f, q.head, visiting)
    f(q)
    pop!(visiting, q)
    nothing
end

function visit(f, qs::Vector{SQLQuery}, visiting)
    for q in qs
        visit(f, q, visiting)
    end
end

visit(f, ::Nothing, visiting) =
    nothing

@generated function visit(f, n::AbstractSQLNode, visiting)
    exs = Expr[]
    for f in fieldnames(n)
        t = fieldtype(n, f)
        if t === SQLQuery || t === Union{SQLQuery, Nothing} || t === Vector{SQLQuery}
            ex = quote
                visit(f, n.$(f), visiting)
            end
            push!(exs, ex)
        end
    end
    push!(exs, :(return nothing))
    Expr(:block, exs...)
end

substitute(q::SQLQuery, c::SQLQuery, c′::SQLQuery) =
    if q.tail === c
        SQLQuery(c′, q.head)
    else
        SQLQuery(q.tail, substitute(q.head, c, c′))
    end

function substitute(qs::Vector{SQLQuery}, c::SQLQuery, c′::SQLQuery)
    i = findfirst(q -> q === c, qs)
    i !== nothing || return qs
    qs′ = copy(qs)
    qs′[i] = c′
    qs′
end

substitute(::Nothing, ::SQLQuery, ::SQLQuery) =
    nothing

@generated function substitute(n::AbstractSQLNode, c::SQLQuery, c′::SQLQuery)
    exs = Expr[]
    fs = fieldnames(n)
    for f in fs
        t = fieldtype(n, f)
        if t === SQLQuery || t === Union{SQLQuery, Nothing}
            ex = quote
                if n.$(f) === c
                    return $n($(Any[Expr(:kw, f′, f′ !== f ? :(n.$(f′)) : :(c′))
                                    for f′ in fs]...))
                end
            end
            push!(exs, ex)
        elseif t === Vector{SQLQuery}
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

Base.show(io::IO, n::Union{AbstractSQLNode, SQLQuery}) =
    print(io, quoteof(n, limit = true))

Base.show(io::IO, ::MIME"text/plain", n::Union{AbstractSQLNode, SQLQuery}) =
    pprint(io, n)

function PrettyPrinting.quoteof(q::SQLQuery; limit::Bool = false, head_only::Bool = false)
    if q.head isa GetNode && !head_only
        q′ = _tosqlgetquery(q)
        if q′ !== nothing
            return quoteof(q′)
        end
    end
    if limit
        ctx = QuoteContext(limit = true)
        ex = quoteof(q.head, ctx)
        if head_only
            ex = Expr(:., ex, QuoteNode(:head))
        elseif q.tail !== nothing
            ex = Expr(:call, :|>, quoteof(q.tail, ctx), ex)
        end
        return ex
    end
    tables_seen = OrderedSet{SQLTable}()
    queries_seen = OrderedSet{SQLQuery}()
    queries_toplevel = Set{SQLQuery}()
    visit(q) do q
        head = q.head
        if head isa FromNode
            source = head.source
            if source isa SQLTable
                push!(tables_seen, source)
            end
        end
        if head isa FromTableNode
            push!(tables_seen, head.table)
        end
        if head isa TabularNode
            push!(queries_seen, q)
            push!(queries_toplevel, q)
        elseif q in queries_seen
            push!(queries_toplevel, q)
        else
            push!(queries_seen, q)
        end
    end
    ctx = QuoteContext()
    defs = Any[]
    if length(queries_toplevel) >= 2 || (length(queries_toplevel) == 1 && !(q in queries_toplevel))
        for t in tables_seen
            def = quoteof(t, limit = true)
            name = t.name
            push!(defs, Expr(:(=), name, def))
            ctx.vars[t] = name
        end
        qidx = 0
        for q in queries_seen
            q in queries_toplevel || continue
            qidx += 1
            ctx.vars[q] = Symbol('q', qidx)
        end
        qidx = 0
        for q in queries_seen
            q in queries_toplevel || continue
            qidx += 1
            name = Symbol('q', qidx)
            def = quoteof(q, ctx, true, true)
            push!(defs, Expr(:(=), name, def))
        end
    end
    ex = quoteof(q, ctx, true, false)
    if head_only
        ex = Expr(:., ex, QuoteNode(:head))
    end
    if !isempty(defs)
        ex = Expr(:let, Expr(:block, defs...), ex)
    end
    ex
end

PrettyPrinting.quoteof(n::AbstractSQLNode; limit::Bool = false) =
    quoteof(convert(SQLQuery, n), limit = limit, head_only = true)

function PrettyPrinting.quoteof(q::SQLQuery, ctx::QuoteContext, top::Bool = false, full::Bool = false)
    if !ctx.limit
        if q.head isa HighlightNode && q.tail !== nothing
            color = q.head.color
            push!(ctx.colors, color)
            ex = quoteof(q.tail, ctx)
            pop!(ctx.colors)
            EscWrapper(ex, color, copy(ctx.colors))
        elseif !full && (local var = get(ctx.vars, q, nothing); var !== nothing)
            var
        elseif !full && !top && q.tail === nothing && q.head isa LiteralNode && q.head.val isa SQLLiteralType
            quoteof(q.head.val)
        elseif q.head isa GetNode && (local q′ = _tosqlgetquery(q); q′) !== nothing
            quoteof(q′)
        else
            ex = quoteof(q.head, ctx)
            if q.tail !== nothing
                ex = Expr(:call, :|>, quoteof(q.tail, ctx), ex)
            end
            ex
        end
    else
        :…
    end
end

PrettyPrinting.quoteof(qs::Vector{SQLQuery}, ctx::QuoteContext) =
    if isempty(qs)
        Any[]
    elseif !ctx.limit
        Any[quoteof(q, ctx) for q in qs]
    else
        Any[:…]
    end


# Errors.

"""
A duplicate label where unique labels are expected.
"""
struct DuplicateLabelError <: FunSQLError
    name::Symbol
    path::Vector{SQLQuery}

    DuplicateLabelError(name; path = SQLQuery[]) =
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
    path::Vector{SQLQuery}

    InvalidArityError(name, expected, actual; path = SQLQuery[]) =
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
        throw(InvalidArityError(n.name, expected, actual, path = SQLQuery[n]))
    end
end

"""
A scalar operation where a tabular operation is expected.
"""
struct IllFormedError <: FunSQLError
    path::Vector{SQLQuery}

    IllFormedError(; path = SQLQuery[]) =
        new(path)
end

function Base.showerror(io::IO, err::IllFormedError)
    print(io, "FunSQL.IllFormedError")
    showpath(io, err.path)
end

"""
A node that cannot be rebased.
"""
struct RebaseError <: FunSQLError
    path::Vector{SQLQuery}

    RebaseError(; path = SQLQuery[]) =
        new(path)
end

function Base.showerror(io::IO, err::RebaseError)
    print(io, "FunSQL.RebaseError")
    showpath(io, err.path)
end

"""
Grouping sets are specified incorrectly.
"""
struct InvalidGroupingSetsError <: FunSQLError
    value::Union{Int, Symbol, Vector{Symbol}}
    path::Vector{SQLQuery}

    InvalidGroupingSetsError(value; path = SQLQuery[]) =
        new(value, path)
end

function Base.showerror(io::IO, err::InvalidGroupingSetsError)
    print(io, "FunSQL.InvalidGroupingSetsError: ")
    value = err.value
    if value isa Int
        print(io, "`$value` is out of bounds")
    elseif value isa Symbol
        print(io, "`$value` is not a valid key")
    elseif value isa Vector{Symbol}
        print(io, "missing keys `$value`")
    end
    showpath(io, err.path)
end

module REFERENCE_ERROR_TYPE

@enum ReferenceErrorType::UInt8 begin
    UNDEFINED_NAME
    UNEXPECTED_ROW_TYPE
    UNEXPECTED_SCALAR_TYPE
    UNEXPECTED_AGGREGATE
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
    path::Vector{SQLQuery}

    ReferenceError(type; name = nothing, path = SQLQuery[]) =
        new(type, name, path)
end

function Base.showerror(io::IO, err::ReferenceError)
    print(io, "FunSQL.ReferenceError: ")
    if err.type == REFERENCE_ERROR_TYPE.UNDEFINED_NAME
        print(io, "cannot find `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE
        print(io, "incomplete reference `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE
        print(io, "unexpected reference after `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.UNEXPECTED_AGGREGATE
        print(io, "aggregate expression requires Group or Partition")
    elseif err.type == REFERENCE_ERROR_TYPE.UNDEFINED_TABLE_REFERENCE
        print(io, "cannot find `$(err.name)`")
    elseif err.type == REFERENCE_ERROR_TYPE.INVALID_TABLE_REFERENCE
        print(io, "table reference `$(err.name)` requires As")
    elseif err.type == REFERENCE_ERROR_TYPE.INVALID_SELF_REFERENCE
        print(io, "self-reference outside of Iterate")
    end
    showpath(io, err.path)
end

function showpath(io, path::Vector{SQLQuery})
    if !isempty(path)
        q = highlight(path)
        println(io, " in:")
        pprint(io, q)
    end
end

function highlight(path::Vector{SQLQuery}, color = Base.error_color())
    @assert !isempty(path)
    q = Highlight(tail = path[end], color = color)
    for k = lastindex(path):-1:2
        q = substitute(path[k - 1], path[k], q)
    end
    q
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
            err = DuplicateLabelError(name, path = SQLQuery[n, arg])
            throw(err)
        end
        label_map[name] = i
    end
    n
end


# Support for query constructors.

struct SQLQueryCtor{N<:AbstractSQLNode}
    id::Symbol
end

Base.show(io::IO, @nospecialize ctor::SQLQueryCtor{N}) where {N} =
    print(io, ctor.id)

(::SQLQueryCtor{N})(args...; tail = nothing, kws...) where {N} =
    SQLQuery(tail, N(args...; kws...))

function dissect(scr::Symbol, ::SQLQueryCtor{N}, pats::Vector{Any}) where {N<:AbstractSQLNode}
    head_pats = Any[]
    tail_pats = Any[]
    for pat in pats
        if pat isa Expr && pat.head === :kw && length(pat.args) == 2 && pat.args[1] === :tail
            push!(tail_pats, pat.args[2])
        else
            push!(head_pats, pat)
        end
    end
    scr_head = gensym(:scr_head)
    head_ex = Expr(:&&, :($scr_head isa $N), Any[dissect(scr_head, pat) for pat in head_pats]...)
    ex = Expr(:&&, :($scr isa SQLQuery), :(local $scr_head = $scr.head; $head_ex))
    if !isempty(tail_pats)
        scr_tail = gensym(:scr_tail)
        tail_ex = Expr(:&&, Any[dissect(scr_tail, pat) for pat in tail_pats]...)
        push!(ex.args, :(local $scr_tail = $scr.tail; $tail_ex))
    end
    ex
end


# The @funsql macro.

struct TransliterateContext
    mod::Module
    src::LineNumberNode
    decl::Bool

    TransliterateContext(mod::Module, src::LineNumberNode, decl::Bool = false) =
        new(mod, src, decl)

    TransliterateContext(ctx::TransliterateContext; src = ctx.src, decl = ctx.decl) =
        new(ctx.mod, src, decl)
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
            return esc(ex)
        elseif ex in (:Inf, :NaN, :missing, :nothing)
            return GlobalRef(Base, ex)
        else
            return QuoteNode(ex)
        end
    elseif @dissect(ex, QuoteNode((local name)::Symbol))
        # :name
        return :(Var($ex))
    elseif ex isa Expr
        if @dissect(ex, Expr(:($), (local arg)))
            # $(...)
            return esc(arg)
        elseif @dissect(ex, Expr(:macrocall, (local ref = GlobalRef($Core, $(Symbol("@doc")))), (local ln)::LineNumberNode, (local doc), (local arg)))
            # "..." ...
            if @dissect(arg, (local name)::Symbol || Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), ::LineNumberNode, (local name)::String))
                arg = Symbol("funsql_$name")
            else
                ctx = TransliterateContext(ctx, src = ln)
                arg = transliterate(arg, ctx)
            end
            return Expr(:macrocall, ref, ln, doc, arg)
        elseif @dissect(ex, Expr(:(=), Expr(:call, (local name)::Symbol || Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), ::LineNumberNode, (local name)::String), (local args)...), (local body)))
            # name(args...) = body
            ctx = TransliterateContext(ctx, decl = true)
            trs = Any[transliterate(arg, ctx) for arg in args]
            ctx = TransliterateContext(ctx, decl = false)
            return Expr(:(=),
                        :($(esc(Symbol("funsql_$name")))($(trs...))),
                        transliterate(body, ctx))
        elseif @dissect(ex, Expr(:(=), (local name)::Symbol, (local arg)))
            # name = arg
            return Expr(:(=), esc(name), transliterate(arg, ctx))
        elseif ctx.decl && @dissect(ex, Expr(:(::), _::Symbol, _))
            # name::t
            return esc(ex)
        elseif @dissect(ex, Expr(:kw, (local key), (local arg)))
            # key = arg
            ctx = TransliterateContext(ctx, decl = true)
            ctx′ = TransliterateContext(ctx, decl = false)
            return Expr(:kw, transliterate(key, ctx), transliterate(arg, ctx′))
        elseif @dissect(ex, Expr(:(...), (local arg)))
            # arg...
            return Expr(:(...), transliterate(arg, ctx))
        elseif @dissect(ex, Expr(:parameters, (local args)...))
            # ; args...
            return Expr(:parameters, Any[transliterate(arg, ctx) for arg in args]...)
        elseif @dissect(ex, Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), ::LineNumberNode, (local name)::String))
            # `name`
            return QuoteNode(Symbol(name))
        elseif @dissect(ex, Expr(:call, Expr(:., (local over), QuoteNode(local name)), (local args)...))
            # over.name(args...)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:call, name, args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:macrocall, Expr(:., (local over), Expr(:quote, (local ex′))), (local args)...))
            # over.`name`
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:macrocall, ex′, args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:., (local over), Expr(:quote, (local arg))))
            # over.`name` (Julia ≥ 1.10)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(arg, ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:call, Expr(:macrocall, Expr(:., (local over), Expr(:quote, (local ex′))), (local args)...), (local args′)...))
            # over.`name`(args...)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:call, Expr(:macrocall, ex′, args...), args′...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:call, Expr(:., (local over), Expr(:quote, (local arg))), (local args)...))
            # over.`name`(args...) (Julia ≥ 1.10)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:call, arg, args...), ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:., (local over), QuoteNode((local name))))
            # over.name
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(name, ctx)
            return :(Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:call, :(=>), (local name = QuoteNode(_::Symbol)), (local arg)))
            # :name => arg
            tr = transliterate(arg, ctx)
            return :($name => $tr)
        elseif @dissect(ex, Expr(:call, :(=>), (local name), (local arg)))
            # name => arg
            tr1 = transliterate(name, ctx)
            tr2 = transliterate(arg, ctx)
            return :($tr1 => $tr2)
        elseif @dissect(ex, Expr(:call, :(:), (local arg1), (local arg2)))
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg2, ctx)
            return :($tr1:$tr2)
        elseif @dissect(ex, Expr(:vect, (local args)...))
            # [args...]
            return Expr(:vect, Any[transliterate(arg, ctx) for arg in args]...)
        elseif @dissect(ex, Expr(:tuple, (local args)...))
            # (args...)
            return Expr(:tuple, Any[transliterate(arg, ctx) for arg in args]...)
        elseif @dissect(ex, Expr(:comparison, (local arg1), (local arg2)::Symbol, (local arg3)))
            # Chained comparison.
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg3, ctx)
            return :($(esc(Symbol("funsql_$arg2")))($tr1, $tr2))
        elseif @dissect(ex, Expr(:comparison, (local arg1), (local arg2)::Symbol, (local arg3), (local args)...))
            # Chained comparison.
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg3, ctx)
            tr3 = transliterate(Expr(:comparison, arg3, args...), ctx)
            return :(Fun(:and, $(esc(Symbol("funsql_$arg2")))($tr1, $tr2), $tr3))
        elseif @dissect(ex, Expr(:(&&), (local args)...))
            # &&(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :(Fun(:and, args = [$(trs...)]))
        elseif @dissect(ex, Expr(:(||), (local args)...))
            # ||(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :(Fun(:or, args = [$(trs...)]))
        elseif @dissect(ex, Expr(:call, (local op = :+ || :-), (local arg = :Inf)))
            # ±Inf
            tr = transliterate(arg, ctx)
            return Expr(:call, op, tr)
        elseif @dissect(ex, Expr(:call, (local name)::Symbol, (local args)...))
            # name(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :($(esc(Symbol("funsql_$name")))($(trs...)))
        elseif @dissect(ex, Expr(:call, Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), ::LineNumberNode, (local name)::String), (local args)...))
            # `name`(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :($(esc(Symbol("funsql_$name")))($(trs...)))
        elseif @dissect(ex, Expr(:block, (local args)...))
            # begin; args...; end
            if all(@dissect(arg, ::LineNumberNode || Expr(:(=), _...) || Expr(:macrocall, GlobalRef($Core, $(Symbol("@doc"))), _...))
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
        elseif @dissect(ex, Expr(:if, (local arg1), (local arg2)))
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg2, ctx)
            return :(Fun(:case, $tr1, $tr2))
        elseif @dissect(ex, Expr(:if, (local arg1), (local arg2), (local arg3)))
            trs = Any[transliterate(arg1, ctx),
                      transliterate(arg2, ctx)]
            while @dissect(arg3, Expr(:if || :elseif, (local arg1′), (local arg2′), (local arg3′)))
                push!(trs,
                      transliterate(arg1′, ctx),
                      transliterate(arg2′, ctx))
                arg3 = arg3′
            end
            if @dissect(arg3, Expr(:if || :elseif, (local arg1′), (local arg2′)))
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
include("nodes/internal.jl")
include("nodes/iterate.jl")
include("nodes/join.jl")
include("nodes/limit.jl")
include("nodes/literal.jl")
include("nodes/order.jl")
include("nodes/over.jl")
include("nodes/partition.jl")
include("nodes/select.jl")
include("nodes/sort.jl")
include("nodes/variable.jl")
include("nodes/where.jl")
include("nodes/with.jl")
include("nodes/with_external.jl")
