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
    ambiguous::Bool

    GetError(name; ambiguous = false) =
        new(name, SQLNode[], ambiguous)
end

function Base.showerror(io::IO, ex::GetError)
    if ex.ambiguous
        print(io, "GetError: ambiguous $(ex.name)")
    else
        print(io, "GetError: cannot find $(ex.name)")
    end
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

default_alias(n::Union{AggregateNode, AsNode, FunctionNode, GetNode}) =
    n.name

default_alias(::AppendNode) =
    :union

default_alias(n::Union{BindNode, DefineNode, GroupNode, HighlightNode, JoinNode, LimitNode, OrderNode, PartitionNode, SelectNode, SortNode, WhereNode}) =
    default_alias(n.over)

default_alias(n::FromNode) =
    n.table.name


# Default export list in the absense of a Select node.

default_list(n::SQLNode) =
    default_list(n[])::Vector{SQLNode}

default_list(::Union{AbstractSQLNode, Nothing}) =
    SQLNode[]

function default_list(n::AppendNode)
    names = [default_alias(col) for col in default_list(n.over)]
    for l in n.list
        seen = Set{Symbol}([default_alias(col) for col in default_list(l)])
        names = [name for name in names if name in seen]
    end
    SQLNode[Get(over = n, name = name) for name in names]
end

default_list(n::Union{BindNode, DefineNode, HighlightNode, LimitNode, OrderNode, PartitionNode, WhereNode}) =
    default_list(n.over)

default_list(n::FromNode) =
    SQLNode[Get(over = n, name = col) for col in n.table.columns]

default_list(n::GroupNode) =
    SQLNode[Get(over = n, name = default_alias(col)) for col in n.by]

default_list(n::JoinNode) =
    vcat(default_list(n.over), default_list(n.joinee))

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

function gather!(refs::Vector{SQLNode}, n::Union{AggregateNode, GetNode})
    push!(refs, n)
end

gather!(refs::Vector{SQLNode}, n::Union{AsNode, HighlightNode, SortNode}) =
    gather!(refs, n.over)

function gather!(refs::Vector{SQLNode}, n::BindNode)
    gather!(refs, n.over)
    gather!(refs, n.list)
end

gather!(refs::Vector{SQLNode}, n::FunctionNode) =
    gather!(refs, n.args)

# Input and output structures for resolution and translation.

mutable struct ResolveContext
    dialect::SQLDialect
    aliases::Dict{Symbol, Int}
    vars::Dict{Symbol, SQLClause}

    ResolveContext(dialect) =
        new(dialect, Dict{Symbol, Int}(), Dict{Symbol, SQLClause}())
end

allocate_alias(ctx::ResolveContext, n) =
    allocate_alias(ctx, default_alias(n))

function allocate_alias(ctx::ResolveContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

struct ResolveRequest
    ctx::ResolveContext
    refs::Vector{SQLNode}
    subs::Dict{SQLNode, SQLClause}
    ambs::Set{SQLNode}

    ResolveRequest(ctx;
                   refs = SQLNode[],
                   subs = Dict{SQLNode, SQLClause}(),
                   ambs = Set{SQLNode}()) =
        new(ctx, refs, subs, ambs)
end

struct ResolveResult
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
    ambs::Set{SQLNode}
end

struct TranslateRequest
    ctx::ResolveContext
    subs::Dict{SQLNode, SQLClause}
    ambs::Set{SQLNode}
end

# Substituting references and translating expressions.

function translate(n::SQLNode, treq)
    try
        c = get(treq.subs, n, nothing)
        if c === nothing
            c = convert(SQLClause, translate(n[], treq))
        end
        c
    catch ex
        if ex isa ErrorWithStack
            push!(ex.stack, n)
        end
        rethrow()
    end
end

translate(ns::Vector{SQLNode}, treq) =
    SQLClause[translate(n, treq) for n in ns]

translate(::Nothing, treq) =
    nothing

translate(n::AggregateNode, treq) =
    translate(Val(n.name), n, treq)

translate(@nospecialize(name::Val{N}), n::AggregateNode, treq) where {N} =
    translate_default(n, treq)

function translate_default(n::AggregateNode, treq)
    args = translate(n.args, treq)
    filter = translate(n.filter, treq)
    AGG(uppercase(string(n.name)), distinct = n.distinct, args = args, filter = filter)
end

function translate(::Val{:count}, n::AggregateNode, treq)
    args = !isempty(n.args) ? translate(n.args, treq) : [OP("*")]
    filter = translate(n.filter, treq)
    AGG(:COUNT, distinct = n.distinct, args = args, filter = filter)
end

translate(n::Union{AsNode, HighlightNode}, treq) =
    translate(n.over, treq)

function translate(n::BindNode, treq)
    vars = treq.ctx.vars
    vars′ = copy(vars)
    for v in n.list
        name = default_alias(v)
        vars′[name] = translate(v, treq)
    end
    treq.ctx.vars = vars′
    c = translate(n.over, treq)
    treq.ctx.vars = vars
    c
end

function translate(n::SubqueryNode, treq)
    req = ResolveRequest(treq.ctx)
    res = resolve(n, req)
    res.clause
end

translate(n::FunctionNode, treq) =
    translate(Val(n.name), n, treq)

translate(@nospecialize(name::Val{N}), n::FunctionNode, treq) where {N} =
    translate_default(n, treq)

function translate_default(n::FunctionNode, treq)
    args = translate(n.args, treq)
    if Base.isidentifier(n.name)
        FUN(uppercase(string(n.name)), args = args)
    else
        OP(n.name, args = args)
    end
end

for (name, op) in (:not => :NOT,
                   :like => :LIKE,
                   :exists => :EXISTS,
                   :(==) => Symbol("="),
                   :(!=) => Symbol("<>"))
    @eval begin
        translate(::Val{$(QuoteNode(name))}, n::FunctionNode, treq) =
            OP($(QuoteNode(op)),
               args = SQLClause[translate(arg, treq) for arg in n.args])
    end
end

for (name, op, default) in ((:and, :AND, true), (:or, :OR, false))
    @eval begin
        function translate(::Val{$(QuoteNode(name))}, n::FunctionNode, treq)
            args = translate(n.args, treq)
            if isempty(args)
                LIT($default)
            elseif length(args) == 1
                args[1]
            else
                OP($(QuoteNode(op)), args = args)
            end
        end
    end
end

for (name, op, default) in (("in", "IN", false), ("not in", "NOT IN", true))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, treq)
            if length(n.args) <= 1
                LIT($default)
            else
                args = translate(n.args, treq)
                if length(args) == 2 && @dissect args[2] (SELECT() || UNION())
                    OP($op, args = args)
                else
                    OP($op, args[1], FUN("", args = args[2:end]))
                end
            end
        end
    end
end

translate(::Val{Symbol("is null")}, n::FunctionNode, treq) =
    OP(:IS, SQLClause[translate(arg, treq) for arg in n.args]..., missing)

translate(::Val{Symbol("is not null")}, n::FunctionNode, treq) =
    OP(:IS, SQLClause[translate(arg, treq) for arg in n.args]..., OP(:NOT, missing))

translate(::Val{:case}, n::FunctionNode, treq) =
    CASE(args = SQLClause[translate(arg, treq) for arg in n.args])

for (name, op) in (("between", "BETWEEN"), ("not between", "NOT BETWEEN"))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, treq)
            if length(n.args) == 3
                args = SQLClause[translate(arg, treq) for arg in n.args]
                OP($op, args[1], args[2], args[3] |> KW(:AND))
            else
                translate_default(n, treq)
            end
        end
    end
end

for (name, op) in (("current_date", "CURRENT_DATE"),
                   ("current_timestamp", "CURRENT_TIMESTAMP"))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, treq)
            if isempty(n.args)
                OP($op)
            else
                translate_default(n, treq)
            end
        end
    end
end

translate(n::SortNode, treq) =
    SORT(over = translate(n.over, treq), value = n.value, nulls = n.nulls)

translate(n::GetNode, treq) =
    throw(GetError(n.name, ambiguous = SQLNode(n) in treq.ambs))

translate(n::LiteralNode, treq) =
    LiteralClause(n.val)

function translate(n::VariableNode, treq)
    c = get(treq.ctx.vars, n.name, nothing)
    if c === nothing
        c = VariableClause(n.name)
    end
    c
end

# Resolving deferred SELECT list.

function make_repl(refs::Vector{SQLNode})::Dict{SQLNode, Symbol}
    repl = Dict{SQLNode, Symbol}()
    dups = Dict{Symbol, Int}()
    for ref in refs
        name′ = name = default_alias(ref)
        k = get(dups, name, 0) + 1
        if k > 1
            name′ = Symbol(name, '_', k)
            while name′ in keys(dups)
                k += 1
                name′ = Symbol(name, '_', k)
            end
            dups[name] = k
        end
        repl[ref] = name
        dups[name′] = 1
    end
    repl
end

function make_repl(trns::Vector{Pair{SQLNode, SQLClause}})::Tuple{Dict{SQLNode, Symbol}, Vector{SQLClause}}
    repl = Dict{SQLNode, Symbol}()
    list = SQLClause[]
    dups = Dict{Symbol, Int}()
    renames = Dict{Tuple{Symbol, SQLClause}, Symbol}()
    for (ref, c) in trns
        name′ = name = default_alias(ref)
        k = get(dups, name, 0) + 1
        if k > 1
            name′ = get(renames, (name, c), nothing)
            if name′ !== nothing
                repl[ref] = name′
                continue
            end
            name′ = Symbol(name, '_', k)
            while name′ in keys(dups)
                k += 1
                name′ = Symbol(name, '_', k)
            end
            dups[name] = k
        end
        push!(list, AS(over = c, name = name′))
        dups[name′] = 1
        renames[name, c] = name′
        repl[ref] = name′
    end
    (repl, list)
end

function resolve(n::SQLNode; dialect = :default)
    ctx = ResolveContext(dialect)
    req = ResolveRequest(ctx, refs = default_list(n))
    resolve(n, req)
end

resolve(n; kws...) =
    resolve(convert(SQLNode, n); kws...)

replace_over(n::SQLNode, over′) =
    convert(SQLNode, replace_over(n[], over′))

replace_over(n::GetNode, over′) =
    GetNode(over = over′, name = n.name)

replace_over(n::AggregateNode, over′) =
    AggregateNode(over = over′, name = n.name, distinct = n.distinct, args = n.args, filter = n.filter)

function deprefix(n::SQLNode, prefix::SQLNode)
    if @dissect n (tail |> (Get() || Agg()))
        if tail === prefix
            return replace_over(n, nothing)
        else
            tail′ = deprefix(tail, prefix)
            if tail′ !== nothing
                return replace_over(n, tail′)
            end
        end
    end
    nothing
end

function deprefix(n::SQLNode, prefix::Symbol)
    if @dissect n (nothing |> Get(name = base_name) |> (Get() || Agg()))
        if base_name === prefix
            return replace_over(n, nothing)
        end
    elseif @dissect n ((tail := Get()) |> (Get() || Agg()))
        tail′ = deprefix(tail, prefix)
        if tail′ !== nothing
            return replace_over(n, tail′)
        end
    elseif @dissect n (tail |> (Get() || Agg()))
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
    req′ = ResolveRequest(req.ctx, refs = refs′, subs = req.subs, ambs = req.ambs)
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
    ambs = Set{SQLNode}()
    for ref in req.refs
        ref′ = get(remaps, ref, nothing)
        ref′ !== nothing || continue
        name = get(res′.repl, ref′, nothing)
        if name !== nothing
            repl[ref] = name
        end
        if ref′ in res′.ambs
            push!(ambs, ref)
        end
    end
    ResolveResult(res′.clause, repl, ambs)
end

function resolve(::Nothing, req)
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    ambs = Set{SQLNode}()
    ResolveResult(c, repl, ambs)
end

function resolve(n::AppendNode, req)
    base_req = ResolveRequest(req.ctx, refs = req.refs)
    base_res = resolve(n.over, base_req)
    as = allocate_alias(req.ctx, n.over)
    results = [as => base_res]
    for l in n.list
        res = resolve(l, base_req)
        as = allocate_alias(req.ctx, l)
        push!(results, as => res)
    end
    refs = req.refs
    ambs = req.refs
    for (as, res) in results
        refs = [ref for ref in refs if ref in keys(res.repl)]
        ambs = [amb for amb in ambs if amb in keys(res.repl) || amb in res.ambs]
    end
    ambs = Set{SQLNode}([amb for amb in ambs if !(amb in refs)])
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in refs
        name = base_res.repl[ref]
        if name in keys(seen)
            other_ref = seen[name]
            if all(res.repl[ref] === res.repl[other_ref] for (as, res) in results)
                dups[ref] = seen[name]
            end
        else
            seen[name] = ref
        end
    end
    urefs = SQLNode[ref for ref in refs if !(ref in keys(dups))]
    repl = make_repl(urefs)
    for (ref, uref) in dups
        repl[ref] = repl[uref]
    end
    cs = SQLClause[]
    for (as, res) in results
        list = SQLClause[]
        for ref in refs
            !(ref in keys(dups)) || continue
            name = repl[ref]
            id = ID(over = as, name = res.repl[ref])
            push!(list, AS(over = id, name = name))
        end
        if isempty(list)
            push!(list, missing)
        end
        c = SELECT(over = FROM(AS(over = res.clause, name = as)),
                   list = list)
        push!(cs, c)
    end
    c = UNION(over = cs[1], all = true, list = cs[2:end])
    ResolveResult(c, repl, ambs)
end

resolve(n::Union{AsNode, HighlightNode}, req) =
    resolve(n.over, req)

function resolve(n::BindNode, req)
    treq = TranslateRequest(req.ctx, req.subs, req.ambs)
    vars = req.ctx.vars
    vars′ = copy(vars)
    for v in n.list
        name = default_alias(v)
        vars′[name] = translate(v, treq)
    end
    treq.ctx.vars = vars′
    res = resolve(n.over, req)
    treq.ctx.vars = vars
    res
end

function resolve(n::DefineNode, req)
    aliases = Symbol[default_alias(col) for col in n.list]
    indexes = Dict{Symbol, Int}()
    for (i, alias) in enumerate(aliases)
        if alias in keys(indexes)
            ex = DuplicateAliasError(alias)
            push!(ex.stack, n.by[i])
            throw(ex)
        end
        indexes[alias] = i
    end
    base_refs = SQLNode[]
    dups = Dict{Symbol, Int}()
    for ref in req.refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(indexes)
            !(name in keys(dups)) || continue
            dups[name] = 1
            col = n.list[indexes[name]]
            gather!(base_refs, col)
        else
            push!(base_refs, ref)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(req.ctx, subs, base_res.ambs)
    repl = Dict{SQLNode, Symbol}()
    ambs = Set{SQLNode}()
    trns = Pair{SQLNode, SQLClause}[]
    tr_cache = Dict{Symbol, SQLClause}()
    base_cache = Dict{Symbol, SQLClause}()
    for ref in req.refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(indexes)
            c = get!(tr_cache, name) do
                col = n.list[indexes[name]]
                translate(col, treq)
            end
            push!(trns, ref => c)
        elseif ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get!(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
        if ref in base_res.ambs
            push!(ambs, ref)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    c = SELECT(over = f, list = list)
    ResolveResult(c, repl, ambs)
end

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
        push!(list, missing)
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
    ambs = Set{SQLNode}()
    ResolveResult(c, repl, ambs)
end

function resolve(n::GroupNode, req)
    aliases = Symbol[default_alias(col) for col in n.by]
    indexes = Dict{Symbol, Int}()
    for (i, alias) in enumerate(aliases)
        if alias in keys(indexes)
            ex = DuplicateAliasError(alias)
            push!(ex.stack, n.by[i])
            throw(ex)
        end
        indexes[alias] = i
    end
    base_refs = SQLNode[]
    has_keys = false
    if !isempty(n.by)
        gather!(base_refs, n.by)
        has_keys = true
    end
    has_aggregates = false
    for ref in req.refs
        if @dissect ref (nothing |> Agg(args = args, filter = filter))
            gather!(base_refs, args)
            if filter !== nothing
                gather!(base_refs, filter)
            end
            has_aggregates = true
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(req.ctx, subs, base_res.ambs)
    if !has_keys && !has_aggregates
        return resolve(nothing, req)
    end
    by = SQLClause[]
    tr_cache = Dict{Symbol, SQLClause}()
    for (i, key) in enumerate(n.by)
        name = aliases[i]
        ckey = translate(key, treq)
        push!(by, ckey)
        tr_cache[name] = ckey
    end
    trns = Pair{SQLNode, SQLClause}[]
    for ref in req.refs
        if @dissect ref (nothing |> Get(name = name))
            if name in keys(indexes)
                ckey = tr_cache[name]
                push!(trns, ref => ckey)
            end
        elseif @dissect ref (nothing |> Agg(name = name))
            c = translate(ref, treq)
            push!(trns, ref => c)
        end
    end
    repl, list = make_repl(trns)
    @assert !isempty(list)
    f = FROM(AS(over = base_res.clause, name = base_as))
    if has_aggregates
        g = GROUP(over = f, by = by)
        c = SELECT(over = g, list = list)
    else
        c = SELECT(over = f, distinct = true, list = list)
    end
    ambs = Set{SQLNode}()
    ResolveResult(c, repl, ambs)
end

function resolve(n::JoinNode, req)
    right_refs = SQLNode[]
    gather!(right_refs, n.on)
    append!(right_refs, req.refs)
    left_refs = copy(right_refs)
    gather!(left_refs, n.joinee)
    lateral = length(left_refs) > length(right_refs)
    left_req = ResolveRequest(req.ctx, refs = left_refs)
    left_res = resolve(n.over, left_req)
    left_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in left_res.repl
        subs[ref] = ID(over = left_as, name = name)
    end
    right_req = ResolveRequest(req.ctx,
                               refs = right_refs,
                               subs = subs,
                               ambs = left_res.ambs)
    right_res = resolve(n.joinee, right_req)
    right_as = allocate_alias(req.ctx, n.joinee)
    ambs = intersect(keys(left_res.repl), keys(right_res.repl))
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in left_res.repl
        !(ref in ambs) || continue
        subs[ref] = ID(over = left_as, name = name)
    end
    for (ref, name) in right_res.repl
        !(ref in ambs) || continue
        subs[ref] = ID(over = right_as, name = name)
    end
    treq = TranslateRequest(req.ctx, subs, ambs)
    on = translate(n.on, treq)
    l_cache = Dict{Symbol, SQLClause}()
    r_cache = Dict{Symbol, SQLClause}()
    trns = Pair{SQLNode, SQLClause}[]
    for ref in req.refs
        !(ref in ambs) || continue
        if ref in keys(left_res.repl)
            name = left_res.repl[ref]
            c = get!(l_cache, name) do
                ID(over = left_as, name = name)
            end
            push!(trns, ref => c)
        elseif ref in keys(right_res.repl)
            name = right_res.repl[ref]
            c = get!(r_cache, name) do
                ID(over = right_as, name = name)
            end
            push!(trns, ref => c)
        else
            continue
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    j = JOIN(over = FROM(AS(over = left_res.clause, name = left_as)),
             joinee = AS(over = right_res.clause, name = right_as),
             on = on,
             left = n.left,
             right = n.right,
             lateral = lateral)
    c = SELECT(over = j, list = list)
    ResolveResult(c, repl, ambs)
end

function resolve(n::LimitNode, req)
    base_req = ResolveRequest(req.ctx, refs = req.refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    ambs = Set{SQLNode}()
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in req.refs
        if ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
        if ref in base_res.ambs
            push!(ambs, ref)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    if n.offset !== nothing || n.limit !== nothing
        l = LIMIT(over = f, offset = n.offset, limit = n.limit)
    else
        l = f
    end
    c = SELECT(over = l, list = list)
    ResolveResult(c, repl, ambs)
end

function resolve(n::OrderNode, req)
    base_refs = SQLNode[]
    gather!(base_refs, n.by)
    append!(base_refs, req.refs)
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(req.ctx, subs, base_res.ambs)
    by = translate(n.by, treq)
    ambs = Set{SQLNode}()
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in req.refs
        if ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
        if ref in base_res.ambs
            push!(ambs, ref)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    if !isempty(by)
        o = ORDER(over = f, by = by)
    else
        o = f
    end
    c = SELECT(over = o, list = list)
    ResolveResult(c, repl, ambs)
end

function resolve(n::PartitionNode, req)
    base_refs = SQLNode[]
    gather!(base_refs, n.by)
    gather!(base_refs, n.order_by)
    for ref in req.refs
        if @dissect ref (nothing |> Agg(args = args, filter = filter))
            gather!(base_refs, args)
            if filter !== nothing
                gather!(base_refs, filter)
            end
        else
            push!(base_refs, ref)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    dups = Dict{Symbol, Int}()
    seen = Set{Symbol}()
    for ref in req.refs
        if @dissect ref (nothing |> Agg(name = name))
            if name in seen
                dups[name] = 1
            else
                push!(seen, name)
            end
        end
    end
    treq = TranslateRequest(req.ctx, subs, base_res.ambs)
    by = translate(n.by, treq)
    order_by = translate(n.order_by, treq)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    ambs = Set{SQLNode}()
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in req.refs
        if @dissect ref (nothing |> Agg(name = name))
            c = partition |> translate(ref, treq)
            push!(trns, ref => c)
        elseif ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get!(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        elseif ref in base_res.ambs
            push!(ambs, ref)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    w = WINDOW(over = FROM(AS(over = base_res.clause, name = base_as)), list = [])
    c = SELECT(over = w, list = list)
    ResolveResult(c, repl, ambs)
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
    for (i, col) in enumerate(n.list)
        gather!(base_refs, col)
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    list = SQLClause[]
    treq = TranslateRequest(req.ctx, subs, base_res.ambs)
    for (i, col) in enumerate(n.list)
        c = translate(col, treq)
        c = AS(over = c, name = aliases[i])
        push!(list, c)
    end
    if isempty(list)
        push!(list, missing)
    end
    c = SELECT(over = FROM(AS(over = base_res.clause, name = base_as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    ambs = Set{SQLNode}()
    for ref in req.refs
        if @dissect ref (nothing |> Get(name = ref_name))
            if ref_name in keys(indexes)
                repl[ref] = ref_name
            end
        end
        if ref in base_res.ambs
            push!(ambs, ref)
        end
    end
    ResolveResult(c, repl, ambs)
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
    treq = TranslateRequest(req.ctx, subs, base_res.ambs)
    condition = translate(n.condition, treq)
    ambs = Set{SQLNode}()
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in req.refs
        if ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
        if ref in base_res.ambs
            push!(ambs, ref)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    w = WHERE(over = FROM(AS(over = base_res.clause, name = base_as)),
              condition = condition)
    c = SELECT(over = w, list = list)
    ResolveResult(c, repl, ambs)
end

