# Translation to SQL syntax tree.


# Rendering SQL query.

function render(n; dialect = :default)
    res = resolve(n, dialect = dialect)
    c = collapse(res.clause)
    render(c, dialect = dialect)
end


# Error types.

abstract type FunSQLError <: Exception
end

abstract type ErrorWithStack <: FunSQLError
end

struct GetError <: ErrorWithStack
    name::Symbol
    stack::Vector{SQLNode}

    GetError(name) =
        new(name, SQLNode[])
end

function Base.showerror(io::IO, ex::GetError)
    print(io, "GetError: cannot find $(ex.name)")
    showstack(io, ex.stack)
end

struct DuplicateAliasError <: ErrorWithStack
    name::Symbol
    stack::Vector{SQLNode}

    DuplicateAliasError(name) =
        new(name, SQLNode[])
end

function Base.showerror(io::IO, ex::DuplicateAliasError)
    print(io, "DuplicateAliasError: $(ex.name)")
    showstack(io, ex.stack)
end

function showstack(io, stack::Vector{SQLNode})
    if !isempty(stack)
        q = highlight(stack)
        println(io, " in:")
        pprint(io, q)
    end
end

function highlight(stack::Vector{SQLNode}, color = Base.error_color())
    @assert !isempty(stack)
    n = Highlight(over = stack[1], color = color)
    for k = 2:lastindex(stack)
        n = substitute(stack[k], stack[k-1], n)
    end
    n
end


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


# Alias for an expression or a subquery.

default_alias(n::SQLNode) =
    default_alias(n[])::Symbol

default_alias(::Union{AbstractSQLNode, Nothing}) =
    :_

default_alias(n::Union{AsNode, CallNode, GetNode}) =
    n.name

default_alias(n::FromNode) =
    n.table.name

default_alias(n::Union{HighlightNode, SelectNode, WhereNode}) =
    default_alias(n.over)


# Default export list in the absense of a Select node.

default_list(n::SQLNode) =
    default_list(n[])::Vector{SQLNode}

default_list(::Union{AbstractSQLNode, Nothing}) =
    SQLNode[]

default_list(n::FromNode) =
    SQLNode[Get(over = n, name = col) for col in n.table.columns]

default_list(n::Union{HighlightNode, WhereNode}) =
    default_list(n.over)

default_list(n::SelectNode) =
    SQLNode[Get(over = n, name = default_alias(col)) for col in n.list]


# Collecting references to resolve.

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

gather!(refs::Vector{SQLNode}, n::Union{AsNode, HighlightNode}) =
    gather!(refs, n.over)

gather!(refs::Vector{SQLNode}, n::CallNode) =
    gather!(refs, n.args)

function gather!(refs::Vector{SQLNode}, n::GetNode)
    push!(refs, n)
end


# Substituting references and translating expressions.

function translate(n::SQLNode, subs)
    try
        c = get(subs, n, nothing)
        if c === nothing
            c = convert(SQLClause, translate(n[], subs))
        end
        c
    catch ex
        if ex isa ErrorWithStack
            push!(ex.stack, n)
        end
        rethrow()
    end
end

translate(n::Union{AsNode, HighlightNode}, subs) =
    translate(n.over, subs)

translate(n::CallNode, subs) =
    OP(n.name, args = SQLClause[translate(arg, subs) for arg in n.args])

translate(n::GetNode, subs) =
    throw(GetError(n.name))

translate(n::LiteralNode, subs) =
    LiteralClause(n.val)


# Resolving deferred SELECT list.

struct ResolveContext
    dialect::SQLDialect
    aliases::Dict{Symbol, Int}

    ResolveContext(dialect) =
        new(dialect, Dict{Symbol, Int}())
end

struct ResolveRequest
    ctx::ResolveContext
    refs::Vector{SQLNode}

    ResolveRequest(ctx; refs = SQLNode[]) =
        new(ctx, refs)
end

struct ResolveResult
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
end

allocate_alias(ctx::ResolveContext, n) =
    allocate_alias(ctx, default_alias(n))

function allocate_alias(ctx::ResolveContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

function resolve(n::SQLNode; dialect = :default)
    ctx = ResolveContext(dialect)
    req = ResolveRequest(ctx, refs = default_list(n))
    resolve(n, req)
end

resolve(n; kws...) =
    resolve(convert(SQLNode, n); kws...)

function deprefix(n::SQLNode, prefix::SQLNode)
    if @dissect n (tail |> Get(name = name))
        if tail === prefix
            return Get(name = name)
        else
            tail′ = deprefix(tail, prefix)
            if tail′ !== nothing
                return Get(over = tail′, name = name)
            end
        end
    end
    nothing
end

function deprefix(n::SQLNode, prefix::Symbol)
    if @dissect n (nothing |> Get(name = base_name) |> Get(name = name))
        if base_name === prefix
            return Get(name = name)
        end
    elseif @dissect n ((tail := Get()) |> Get(name = name))
        tail′ = deprefix(tail, prefix)
        if tail′ !== nothing
            return Get(over = tail′, name = name)
        end
    elseif @dissect n (tail |> Get(name = name))
        if tail !== nothing
            return n
        end
    end
    nothing
end

deprefix(::Nothing, prefix) =
    nothing

deprefix(n::SQLNode, prefix::SQLNode, ::Nothing) =
    something(deprefix(n, prefix), n)

function deprefix(n::SQLNode, node_prefix::SQLNode, alias_prefix::Symbol)
    n′ = deprefix(n, node_prefix)
    if n′ === nothing
        n′ = deprefix(n, alias_prefix)
    end
    n′
end

function resolve(n::SQLNode, req)
    alias_prefix = nothing
    @dissect n As(name = alias_prefix)
    remaps = Dict{SQLNode, SQLNode}()
    refs′ = SQLNode[]
    for ref in req.refs
        !(ref in keys(remaps)) || continue
        ref′ = deprefix(ref, n, alias_prefix)
        if ref′ !== nothing
            remaps[ref] = ref′
            push!(refs′, ref′)
        end
    end
    req′ = ResolveRequest(req.ctx, refs = refs′)
    res′ =
        try
            resolve(n[], req′)::ResolveResult
        catch ex
            if ex isa ErrorWithStack
                push!(ex.stack, n)
            end
            rethrow()
        end
    repl = Dict{SQLNode, Symbol}()
    for ref in req.refs
        ref′ = get(remaps, ref, nothing)
        ref′ !== nothing || continue
        name = get(res′.repl, ref′, nothing)
        if name !== nothing
            repl[ref] = name
        end
    end
    ResolveResult(res′.clause, repl)
end

function resolve(::Nothing, req)
    c = SELECT(list = SQLClause[true])
    repl = Dict{SQLNode, Symbol}()
    ResolveResult(c, repl)
end

resolve(n::Union{AsNode, HighlightNode}, req) =
    resolve(n.over, req)

function resolve(n::FromNode, req)
    output_columns = Set{Symbol}()
    for ref in req.refs
        if @dissect ref (nothing |> Get(name = ref_name))
            if ref_name in n.table.column_set && !(ref_name in output_columns)
                push!(output_columns, ref_name)
            end
        end
    end
    as = allocate_alias(req.ctx, n.table.name)
    list = SQLClause[AS(over = ID(over = as, name = col), name = col)
                     for col in n.table.columns
                     if col in output_columns]
    if isempty(list)
        push!(list, true)
    end
    tbl = ID(over = n.table.schema, name = n.table.name)
    c = SELECT(over = FROM(AS(over = tbl, name = as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in req.refs
        if @dissect ref (nothing |> Get(name = ref_name))
            if ref_name in output_columns
                repl[ref] = ref_name
            end
        end
    end
    ResolveResult(c, repl)
end

function resolve(n::SelectNode, req)
    aliases = Symbol[default_alias(col) for col in n.list]
    indexes = Dict{Symbol, Int}()
    for (i, alias) in enumerate(aliases)
        if alias in keys(indexes)
            ex = DuplicateAliasError(alias)
            push!(ex.stack, n.list[i])
            throw(ex)
        end
        indexes[alias] = i
    end
    base_refs = SQLNode[]
    output_indexes = Set{Int}()
    for ref in req.refs
        if @dissect ref (nothing |> Get(name = ref_name))
            if ref_name in keys(indexes)
                push!(output_indexes, indexes[ref_name])
            end
        end
    end
    for (i, col) in enumerate(n.list)
        if i in output_indexes
            gather!(base_refs, col)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    list = SQLClause[]
    for (i, col) in enumerate(n.list)
        i in output_indexes || continue
        c = translate(col, subs)
        c = AS(over = c, name = aliases[i])
        push!(list, c)
    end
    if isempty(list)
        push!(list, true)
    end
    c = SELECT(over = FROM(AS(over = base_res.clause, name = base_as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in req.refs
        if @dissect ref (nothing |> Get(name = ref_name))
            if ref_name in keys(indexes)
                repl[ref] = ref_name
            end
        end
    end
    ResolveResult(c, repl)
end

function resolve(n::WhereNode, req)
    base_refs = SQLNode[]
    gather!(base_refs, n.condition)
    append!(base_refs, req.refs)
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    condition = translate(n.condition, subs)
    list = SQLClause[]
    repl = Dict{SQLNode, Symbol}()
    seen = Set{Symbol}()
    for ref in req.refs
        if ref in keys(base_res.repl)
            name = base_res.repl[ref]
            repl[ref] = name
            !(name in seen) || continue
            push!(seen, name)
            id = ID(over = base_as, name = name)
            push!(list, AS(over = id, name = name))
        end
    end
    if isempty(list)
        push!(list, true)
    end
    w = WHERE(over = FROM(AS(over = base_res.clause, name = base_as)),
              condition = condition)
    c = SELECT(over = w, list = list)
    ResolveResult(c, repl)
end

