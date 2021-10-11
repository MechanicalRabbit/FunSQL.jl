# Translation to SQL syntax tree.


# Input and output structures for resolution and translation.

mutable struct BuildContext
    dialect::SQLDialect
    aliases::Dict{Symbol, Int}
    vars::Dict{Symbol, SQLClause}

    BuildContext(dialect) =
        new(dialect, Dict{Symbol, Int}(), Dict{Symbol, SQLClause}())
end

allocate_alias(ctx::BuildContext, n) =
    allocate_alias(ctx, label(n))

function allocate_alias(ctx::BuildContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

struct BuildRequest
    ctx::BuildContext
    refs::Vector{SQLNode}
    subs::Dict{SQLNode, SQLClause}

    BuildRequest(ctx;
                   refs = SQLNode[],
                   subs = Dict{SQLNode, SQLClause}()) =
        new(ctx, refs, subs)
end

struct BuildResult
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
end

struct TranslateRequest
    ctx::BuildContext
    subs::Dict{SQLNode, SQLClause}
end

# Substituting references and translating expressions.

function translate(n::SQLNode, treq)
    c = get(treq.subs, n, nothing)
    if c === nothing
        c = convert(SQLClause, translate(n[], treq))
    end
    c
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
        name = label(v)
        vars′[name] = translate(v, treq)
    end
    treq.ctx.vars = vars′
    c = translate(n.over, treq)
    treq.ctx.vars = vars
    c
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
        name′ = name = label(ref)
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
        name′ = name = label(ref)
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


# Building a SQL query out of a SQL node tree.

function render(n; dialect = :default)
    actx = AnnotateContext()
    n′ = annotate(actx, convert(SQLNode, n))
    resolve!(actx)
    link!(actx)
    ctx = BuildContext(dialect)
    res = build(n′, ctx)
    c = collapse(res.clause)
    sql = render(c, dialect = dialect)
    sql
end

# Building SQL clauses.

build(n::SQLNode, ctx::BuildContext) =
    build(n[], ctx)

build(n::SQLNode, treq::TranslateRequest) =
    build(n[], treq)

function build(::Nothing, ctx::BuildContext)
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    BuildResult(c, repl)
end

build(n::SQLNode, ctx::Union{BuildContext, TranslateRequest}, refs::Vector{SQLNode}) =
    build(n[], ctx, refs)

build(n::SubqueryNode, treq::TranslateRequest, refs::Vector{SQLNode}) =
    build(n, treq.ctx, refs)

translate(n::BoxNode, treq::TranslateRequest) =
    build(n, treq).clause

function build(n::BoxNode, ctx::BuildContext)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = build(n.over, ctx, refs′)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    BuildResult(res.clause, repl′)
end

function build(n::BoxNode, treq::TranslateRequest)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = build(n.over, treq, refs′)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(node = node)) && handle == n.handle
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    BuildResult(res.clause, repl′)
end

function build(::Nothing, ctx::BuildContext, refs::Vector{SQLNode})
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    BuildResult(c, repl)
end

function build(n::AppendNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    as = allocate_alias(ctx, n.over)
    results = [as => base_res]
    for l in n.list
        res = build(l, ctx)
        as = allocate_alias(ctx, l)
        push!(results, as => res)
    end
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
    BuildResult(c, repl)
end

function build(n::AsNode, ctx::Union{BuildContext, TranslateRequest}, refs::Vector{SQLNode})
    res = build(n.over, ctx)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect ref over |> NameBound()
            @assert over !== nothing
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    BuildResult(res.clause, repl′)
end

function build(n::BindNode, treq::TranslateRequest, refs::Vector{SQLNode})
    ctx = treq.ctx
    vars = ctx.vars
    vars′ = copy(vars)
    for v in n.list
        name = label(v)
        vars′[name] = translate(v, treq)
    end
    ctx.vars = vars′
    res = build(n.over, ctx)
    ctx.vars = vars
    res
end

build(n::BindNode, ctx::BuildContext, refs::Vector{SQLNode}) =
    build(n, TranslateRequest(ctx, Dict{SQLNode, SQLClause}()), refs)

function build(n::DefineNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    tr_cache = Dict{Symbol, SQLClause}()
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            c = get!(tr_cache, name) do
                col = n.list[n.label_map[name]]
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
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    c = SELECT(over = f, list = list)
    BuildResult(c, repl)
end

function build(n::FromNode, ctx::BuildContext, refs::Vector{SQLNode})
    output_columns = Set{Symbol}()
    for ref in refs
        match = @dissect ref (nothing |> Get(name = name))
        @assert match && name in n.table.column_set
        if !(name in output_columns)
            push!(output_columns, name)
        end
    end
    as = allocate_alias(ctx, n.table.name)
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
    for ref in refs
        if @dissect ref (nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    BuildResult(c, repl)
end

function build(n::GroupNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    by = SQLClause[]
    tr_cache = Dict{Symbol, SQLClause}()
    for (i, name) in enumerate(keys(n.label_map))
        key = n.by[i]
        ckey = translate(key, treq)
        push!(by, ckey)
        tr_cache[name] = ckey
    end
    has_keys = !isempty(by)
    has_aggregates = false
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if @dissect ref (nothing |> Get(name = name))
            @assert name in keys(n.label_map)
            ckey = tr_cache[name]
            push!(trns, ref => ckey)
        elseif @dissect ref (nothing |> Agg(name = name))
            c = translate(ref, treq)
            push!(trns, ref => c)
            has_aggregates = true
        end
    end
    if !has_keys && !has_aggregates
        return build(nothing, ctx)
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
    BuildResult(c, repl)
end

build(n::HighlightNode, ctx::BuildContext, refs::Vector{SQLNode}) =
    build(n.over, ctx)

function build(n::ExtendedJoinNode, ctx::BuildContext, refs::Vector{SQLNode})
    left_res = build(n.over, ctx)
    left_as = allocate_alias(ctx, n.over)
    lateral = !isempty(n.lateral)
    if lateral
        lsubs = Dict{SQLNode, SQLClause}()
        for ref in n.lateral
            name = left_res.repl[ref]
            lsubs[ref] = ID(over = left_as, name = name)
        end
        treq = TranslateRequest(ctx, lsubs)
        right_res = build(n.joinee, treq)
    else
        right_res = build(n.joinee, ctx)
    end
    right_as = allocate_alias(ctx, n.joinee)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in left_res.repl
        subs[ref] = ID(over = left_as, name = name)
    end
    for (ref, name) in right_res.repl
        subs[ref] = ID(over = right_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    on = translate(n.on, treq)
    l_cache = Dict{Symbol, SQLClause}()
    r_cache = Dict{Symbol, SQLClause}()
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
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
            error()
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
    BuildResult(c, repl)
end

function build(n::LimitNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        name = base_res.repl[ref]
        c = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
        push!(trns, ref => c)
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
    BuildResult(c, repl)
end

function build(n::OrderNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    by = translate(n.by, treq)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        name = base_res.repl[ref]
        c = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
        push!(trns, ref => c)
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
    BuildResult(c, repl)
end

function build(n::PartitionNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    by = translate(n.by, treq)
    order_by = translate(n.order_by, treq)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if @dissect ref (nothing |> Agg(name = name))
            c = partition |> translate(ref, treq)
            push!(trns, ref => c)
        else
            @assert ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get!(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    w = WINDOW(over = FROM(AS(over = base_res.clause, name = base_as)), list = [])
    c = SELECT(over = w, list = list)
    BuildResult(c, repl)
end

function build(n::SelectNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    list = SQLClause[]
    treq = TranslateRequest(ctx, subs)
    for (i, name) in enumerate(keys(n.label_map))
        col = n.list[i]
        c = translate(col, treq)
        c = AS(over = c, name = name)
        push!(list, c)
    end
    if isempty(list)
        push!(list, missing)
    end
    c = SELECT(over = FROM(AS(over = base_res.clause, name = base_as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        ref_name = nothing
        @dissect ref (nothing |> Get(name = name))
        @assert name !== nothing
        repl[ref] = name
    end
    BuildResult(c, repl)
end

function build(n::WhereNode, ctx::BuildContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    condition = translate(n.condition, treq)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        @assert ref in keys(base_res.repl)
        name = base_res.repl[ref]
        c = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
        push!(trns, ref => c)
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    w = WHERE(over = FROM(AS(over = base_res.clause, name = base_as)),
              condition = condition)
    c = SELECT(over = w, list = list)
    BuildResult(c, repl)
end

