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
        name = pop!(path)
        ex = Expr(:., ex, QuoteNode(Base.isidentifier(name) ? name : string(name)))
    end
    ex
end


# Traversing query tree.

function children(q::SQLQuery)
    cs = SQLQuery[]
    if q.tail !== nothing
        push!(cs, q.tail)
    end
    children!(q.head, cs)
    cs
end

@generated function children!(n::AbstractSQLNode, children::Vector{SQLQuery})
    exs = Expr[]
    for f in fieldnames(n)
        t = fieldtype(n, f)
        if t === SQLQuery
            push!(exs, quote push!(children, n.$(f)) end)
        elseif t === Union{SQLQuery, Nothing}
            push!(
                exs,
                quote
                    if n.$(f) !== nothing
                        push!(children, n.$(f))
                    end
                end)
        elseif t === Vector{SQLQuery}
            push!(exs, quote append!(children, n.$(f)) end)
        end
    end
    push!(exs, :(return nothing))
    Expr(:block, exs...)
end


# Pretty-printing.

Base.show(io::IO, q::SQLQuery) =
    print(io, quoteof(q, limit = true))

function Base.show(io::IO, ::MIME"text/plain", q::SQLQuery)
    if q isa SQLQuery && q.tail === nothing && q.head isa FunSQLMacroNode
        println(io, q.head.line)
    end
    pprint(io, q)
end

function PrettyPrinting.quoteof(q::SQLQuery; limit::Bool = false)
    if limit
        ctx = QuoteContext(limit = true)
        ex = quoteof(q.head, ctx)
        if q.tail !== nothing
            ex = Expr(:call, :|>, quoteof(q.tail, ctx), ex)
        end
        return ex
    end
    skip_to = Dict{SQLQuery, SQLQuery}()
    tables_seen = OrderedSet{SQLTable}()
    queries_seen = OrderedSet{SQLQuery}()
    queries_toplevel = Set{SQLQuery}()
    highlight_targets = Dict{SQLQuery, Symbol}()
    highlight_colors = Dict{SQLQuery, Vector{Symbol}}()
    color_stack = [:normal]
    unwrap_depth = [0]
    unwrapped = Set{SQLQuery}()
    stack = [(q, true)]
    while !isempty(stack)
        top, fwd = pop!(stack)
        head = top.head
        if fwd
            push!(stack, (top, false))
            if head isa HighlightNode && top.tail !== nothing
                highlight_targets[top.tail] = head.color
            elseif head isa HighlightTargetNode && head.target isa SQLQuery
                highlight_targets[head.target] = head.color
            elseif head isa UnwrapFunSQLMacroNode
                push!(unwrap_depth, head.depth)
            elseif head isa FunSQLMacroNode
                push!(unwrap_depth, unwrap_depth[end] != 0 ? unwrap_depth[end]-1 : 0)
            end
            color = get(highlight_targets, top, nothing)
            if color !== nothing
                push!(color_stack, color)
                highlight_colors[top] = copy(color_stack)
            end
            if !(top in queries_seen)
                if head isa FunSQLMacroNode
                    if unwrap_depth[end-1] != 0
                        push!(stack, (head.query, true))
                    end
                    if top.tail !== nothing
                        push!(stack, (top.tail, true))
                    end
                else
                    for c in reverse(children(top))
                        push!(stack, (c, true))
                    end
                end
            end
        else
            if head isa Union{HighlightNode, HighlightTargetNode, UnwrapFunSQLMacroNode} && top.tail !== nothing
                skip_to[top] = get(skip_to, top.tail, top.tail)
                if top in keys(highlight_colors)
                    highlight_colors[skip_to[top]] = highlight_colors[top]
                end
            end
            if head isa Union{FunSQLMacroNode, UnwrapFunSQLMacroNode}
                pop!(unwrap_depth)
            end
            if head isa FunSQLMacroNode && unwrap_depth[end] != 0
                push!(unwrapped, top)
                if top.tail === nothing
                    skip_to[top] = get(skip_to, head.query, head.query)
                end
            end
            if top in keys(highlight_targets)
                pop!(color_stack)
            end
            if head isa FromNode && head.source isa SQLTable
                push!(tables_seen, head.source)
            elseif head isa FromTableNode
                push!(tables_seen, head.table)
            end
            if head isa FunSQLMacroNode
                push!(queries_toplevel, top)
                if top.tail !== nothing
                    push!(queries_toplevel, get(skip_to, top.tail, top.tail))
                end
            elseif head isa TabularNode && top.tail !== nothing
                push!(queries_toplevel, get(skip_to, top.tail, top.tail))
            end
            if top in queries_seen || isempty(stack)
                push!(queries_toplevel, get(skip_to, top, top))
            end
            push!(queries_seen, top)
        end
    end
    ctx = QuoteContext()
    defs = Any[]
    for t in collect(tables_seen)
        def = quoteof(t, limit = true)
        name = t.name
        push!(defs, Expr(:(=), name, def))
        ctx.repl[t] = name
    end
    qidx = 0
    for q in queries_seen
        if q in keys(skip_to)
            ex = ctx.repl[skip_to[q]]
            ctx.repl[q] = ex
        else
            toplevel = q in queries_toplevel
            if !toplevel && q.tail === nothing && q.head isa LiteralNode && q.head.val isa SQLLiteralType
                ex = quoteof(q.head.val)
            elseif q.head isa GetNode && q.tail !== nothing && (local tail_ex = ctx.repl[q.tail]; tail_ex isa Expr && tail_ex.head === :.)
                ex = Expr(:., tail_ex, QuoteNode(Base.isidentifier(q.head.name) ? q.head.name : string(q.head.name)))
            elseif q.head isa FunSQLMacroNode && q in unwrapped
                ex = ctx.repl[q.head.query]
                if q.tail !== nothing
                    ex = Expr(:call, :|>, quoteof(q.tail, ctx), ex)
                end
            else
                ex = quoteof(q, ctx)
            end
            colors = get(highlight_colors, q, nothing)
            if colors !== nothing
                ex = EscWrapper(ex, colors[end], colors[1:end-1])
                if toplevel
                    ex = NormalWrapper(ex)
                end
            end
            if toplevel
                qidx += 1
                name = Symbol('q', qidx)
                push!(defs, Expr(:(=), name, ex))
                ex = name
            end
            ctx.repl[q] = ex
        end
    end
    ex = ctx.repl[q]
    if length(defs) == 1
        ex = pop!(defs).args[2]
    end
    if !isempty(defs)
        ex = Expr(:let, Expr(:block, defs...), ex)
    end
    ex
end

function PrettyPrinting.quoteof(q::SQLQuery, ctx::QuoteContext)
    if !ctx.limit
        if (local ex = get(ctx.repl, q, nothing); ex !== nothing)
            ex
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

Base.show(io::IO, n::AbstractSQLNode) =
    print(io, quoteof(n))

function Base.show(io::IO, ::MIME"text/plain", n::AbstractSQLNode)
    if n isa FunSQLMacroNode
        println(io, n.line)
    end
    pprint(io, n)
end

PrettyPrinting.quoteof(@nospecialize n::AbstractSQLNode) =
    Expr(:., quoteof(convert(SQLQuery, n), limit = true), QuoteNode(:head))


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
    stack = SQLQuery[]
    while !isempty(path)
        top = path[1]
        if top.head isa FunSQLMacroNode
            k = 1
            for (i, q) in enumerate(path)
                if q.head isa FunSQLMacroNode && q.head.base === top.head.base
                    if q.tail === nothing || !(q.tail in path)
                        top = q
                        k = i
                    end
                end
            end
            push!(stack, SQLQuery(top.head))
            path = path[k+1:end]
        else
            push!(stack, top |> HighlightTarget(path[end], :red))
            k = lastindex(path)+1
            for (i, q) in enumerate(path)
                if q.head isa FunSQLMacroNode
                    if q.tail === nothing || !(q.tail in path)
                        k = i
                        break
                    end
                end
            end
            path = path[k:end]
        end
    end
    while !isempty(stack)
        q = pop!(stack)
        if q.head isa FunSQLMacroNode
            print(io, " at $(relpath(string(q.head.line.file))):$(q.head.line.line)")
            if q.head.def !== nothing
                print(io, " in $(q.head.def)")
            end
            println(io, ":")
        else
            println(io, " in:")
        end
        pprint(io, q)
        if !isempty(stack)
            println(io)
            print(io, "#")
        end
    end
end

"""
Invalid application of the [`@funsql`](@ref) macro.
"""
struct TransliterationError <: FunSQLError
    expr::Any
    src::LineNumberNode
end

function Base.showerror(io::IO, err::TransliterationError)
    println(io, "FunSQL.TransliterationError: ill-formed @funsql notation at $(relpath(string(err.src.file))):$(err.src.line):")
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
    def::Union{Symbol, Nothing}
    base::LineNumberNode
    line::LineNumberNode
    decl::Bool

    TransliterateContext(mod::Module, line::LineNumberNode, decl::Bool = false) =
        new(mod, nothing, line, line, decl)

    TransliterateContext(ctx::TransliterateContext; def = ctx.def, base = ctx.base, line = ctx.line, decl = ctx.decl) =
        new(ctx.mod, def, base, line, decl)
end

"""
    @funsql ex

Assemble a FunSQL query using convenient macro notation.
"""
macro funsql(ex)
    ctx = TransliterateContext(__module__, __source__)
    if transliterate_is_definition(ex)
        transliterate_definition(ex, ctx)
    else
        transliterate_toplevel(ex, ctx)
    end
end

"""
    @funsql db ex args...

Assemble and execute a FunSQL query using convenient macro notation.
"""
macro funsql(db, ex, args...)
    ctx = TransliterateContext(__module__, __source__)
    q = transliterate_toplevel(ex, ctx)
    args = Any[transliterate_parameter(arg, ctx) for arg in args]
    Expr(:call, DBInterface.execute, esc(db), q, args...)
end

function transliterate_is_definition(@nospecialize(ex))
    ex isa Expr || return false
    if @dissect(ex, Expr(:(=), Expr(:call, _...), _))
        return true
    end
    if @dissect(ex, Expr(:macrocall, GlobalRef($Core, $(Symbol("@doc"))), _, _, (local arg)))
        if @dissect(arg, ::Symbol || Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), _, _))
            return true
        end
        if @dissect(arg, Expr(:(=), Expr(:call, _...), _))
            return true
        end
    end
    if @dissect(ex, Expr(:block, (local args)...))
        for arg in args
            !(arg isa LineNumberNode) || continue
            return transliterate_is_definition(arg)
        end
    end
    return false
end

function transliterate_toplevel(@nospecialize(ex), ctx)
    ex′ = transliterate(ex, ctx)
    quote
        let q = $ex′
            if q isa $(Union{SQLQuery, SQLGetQuery})
                $FunSQLMacro(
                    q,
                    $(QuoteNode(ex)),
                    $(ctx.mod),
                    $(ctx.def !== nothing ? QuoteNode(ctx.def) : nothing),
                    $(QuoteNode(ctx.base)),
                    $(QuoteNode(ctx.line)))
            else
                q
            end
        end
    end
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
        return :($Var($ex))
    elseif ex isa Expr
        if @dissect(ex, Expr(:($), (local arg)))
            # $(...)
            return esc(arg)
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
            return :($Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:macrocall, Expr(:., (local over), Expr(:quote, (local ex′))), (local args)...))
            # over.`name`
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:macrocall, ex′, args...), ctx)
            return :($Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:., (local over), Expr(:quote, (local arg))))
            # over.`name` (Julia ≥ 1.10)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(arg, ctx)
            return :($Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:call, Expr(:macrocall, Expr(:., (local over), Expr(:quote, (local ex′))), (local args)...), (local args′)...))
            # over.`name`(args...)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:call, Expr(:macrocall, ex′, args...), args′...), ctx)
            return :($Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:call, Expr(:., (local over), Expr(:quote, (local arg))), (local args)...))
            # over.`name`(args...) (Julia ≥ 1.10)
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(Expr(:call, arg, args...), ctx)
            return :($Chain($tr1, $tr2))
        elseif @dissect(ex, Expr(:., (local over), QuoteNode((local name))))
            # over.name
            tr1 = transliterate(over, ctx)
            tr2 = transliterate(name, ctx)
            return :($Chain($tr1, $tr2))
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
            return :($Fun(:and, $(esc(Symbol("funsql_$arg2")))($tr1, $tr2), $tr3))
        elseif @dissect(ex, Expr(:(&&), (local args)...))
            # &&(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :($Fun(:and, args = [$(trs...)]))
        elseif @dissect(ex, Expr(:(||), (local args)...))
            # ||(args...)
            trs = Any[transliterate(arg, ctx) for arg in args]
            return :($Fun(:or, args = [$(trs...)]))
        elseif @dissect(ex, Expr(:(:=), (local arg1), (local arg2)))
            # arg1 := arg2
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg2, ctx)
            return :($(esc(Symbol("funsql_:=")))($tr1, $tr2))
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
            tr = nothing
            for arg in args
                if arg isa LineNumberNode
                    ctx = TransliterateContext(ctx, line = arg)
                else
                    tr′ = Expr(:block, ctx.line, transliterate_toplevel(arg, ctx))
                    tr = tr !== nothing ? :($Chain($tr, $tr′)) : tr′
                end
            end
            return tr
        elseif @dissect(ex, Expr(:if, (local arg1), (local arg2)))
            tr1 = transliterate(arg1, ctx)
            tr2 = transliterate(arg2, ctx)
            return :($Fun(:case, $tr1, $tr2))
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
            return :($Fun(:case, $(trs...)))
        end
    end
    throw(TransliterationError(ex, ctx.line))
end

function transliterate_definition(@nospecialize(ex), ctx)
    if ex isa Expr
        if @dissect(ex, Expr(:macrocall, (local ref = GlobalRef($Core, $(Symbol("@doc")))), (local ln)::LineNumberNode, (local doc), (local arg)))
            # "..." ...
            if @dissect(arg, (local name)::Symbol || Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), ::LineNumberNode, (local name)::String))
                arg = Symbol("funsql_$name")
            else
                ctx = TransliterateContext(ctx, line = ln)
                arg = transliterate_definition(arg, ctx)
            end
            return Expr(:macrocall, ref, ln, doc, arg)
        elseif @dissect(ex, Expr(:(=), Expr(:call, (local name)::Symbol || Expr(:macrocall, GlobalRef($Core, $(Symbol("@cmd"))), ::LineNumberNode, (local name)::String), (local args)...), (local body)))
            # name(args...) = body
            ctx = TransliterateContext(ctx, decl = true)
            trs = Any[transliterate(arg, ctx) for arg in args]
            ctx = TransliterateContext(ctx, def = Symbol(name), decl = false)
            return Expr(:(=),
                        :($(esc(Symbol("funsql_$name")))($(trs...))),
                        transliterate_toplevel(body, ctx))
        elseif @dissect(ex, Expr(:block, (local args)...))
            # begin; args...; end
            trs = Any[]
            for arg in args
                if arg isa LineNumberNode
                    ctx = TransliterateContext(ctx, base = arg, line = arg)
                    push!(trs, arg)
                else
                    push!(trs, transliterate_definition(arg, ctx))
                end
            end
            return Expr(:block, trs...)
        end
    end
    throw(TransliterationError(ex, ctx.line))
end

function transliterate_parameter(@nospecialize(ex), ctx)
    if @dissect(ex, Expr(:kw || :(=), (local key), (local arg)))
        Expr(:kw, esc(key), esc(arg))
    else
        esc(ex)
    end
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
