
function render(n; dialect = :default)
    actx = AnnotateContext()
    n′ = annotate(actx, convert(SQLNode, n))
    resolve!(actx)
    link!(actx)
    tctx = TranslateContext(dialect, actx.path_map)
    c = translate(n′, tctx)
    c = collapse(c)
    sql = render(c, dialect = dialect)
    sql
end

struct TranslateContext
    dialect::SQLDialect
    path_map::PathMap
    aliases::Dict{Symbol, Int}
    vars::Dict{Symbol, SQLClause}
    subs::Dict{SQLNode, SQLClause}

    TranslateContext(dialect, path_map::PathMap) =
        new(dialect, path_map, Dict{Symbol, Int}(), Dict{Symbol, SQLClause}(), Dict{SQLNode, SQLClause}())

    function TranslateContext(ctx::TranslateContext; vars = nothing, subs = nothing)
        new(ctx.dialect, ctx.path_map, ctx.aliases, something(vars, ctx.vars), something(subs, ctx.subs))
    end
end

allocate_alias(ctx::TranslateContext, n::SQLNode) =
    allocate_alias(ctx, (n[]::BoxNode).type.name)

function allocate_alias(ctx::TranslateContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

function translate(n, ctx::TranslateContext, subs::Dict{SQLNode, SQLClause})
    ctx′ = TranslateContext(ctx, subs = subs)
    translate(n, ctx′)
end

function translate(n::SQLNode, ctx::TranslateContext)
    c = get(ctx.subs, n, nothing)
    if c === nothing
        c = convert(SQLClause, translate(n[], ctx))
    end
    c
end

translate(ns::Vector{SQLNode}, ctx::TranslateContext) =
    SQLClause[translate(n, ctx) for n in ns]

translate(::Nothing, ::TranslateContext) =
    nothing

translate(n::AggregateNode, ctx) =
    translate(Val(n.name), n, ctx)

translate(@nospecialize(name::Val{N}), n::AggregateNode, ctx) where {N} =
    translate_default(n, ctx)

function translate_default(n::AggregateNode, ctx)
    args = translate(n.args, ctx)
    filter = translate(n.filter, ctx)
    AGG(uppercase(string(n.name)), distinct = n.distinct, args = args, filter = filter)
end

function translate(::Val{:count}, n::AggregateNode, ctx)
    args = !isempty(n.args) ? translate(n.args, ctx) : [OP("*")]
    filter = translate(n.filter, ctx)
    AGG(:COUNT, distinct = n.distinct, args = args, filter = filter)
end

translate(n::Union{AsNode, HighlightNode}, ctx) =
    translate(n.over, ctx)

function translate(n::BindNode, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.list[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    translate(n.over, ctx′)
end

function translate(n::BoxNode, ctx::TranslateContext)
    res = assemble(n, ctx)
    res.clause
end

translate(n::FunctionNode, ctx) =
    translate(Val(n.name), n, ctx)

translate(@nospecialize(name::Val{N}), n::FunctionNode, ctx) where {N} =
    translate_default(n, ctx)

function translate_default(n::FunctionNode, ctx)
    args = translate(n.args, ctx)
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
        translate(::Val{$(QuoteNode(name))}, n::FunctionNode, ctx) =
            OP($(QuoteNode(op)),
               args = SQLClause[translate(arg, ctx) for arg in n.args])
    end
end

for (name, op, default) in ((:and, :AND, true), (:or, :OR, false))
    @eval begin
        function translate(::Val{$(QuoteNode(name))}, n::FunctionNode, ctx)
            args = translate(n.args, ctx)
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
        function translate(::Val{Symbol($name)}, n::FunctionNode, ctx)
            if length(n.args) <= 1
                LIT($default)
            else
                args = translate(n.args, ctx)
                if length(args) == 2 && @dissect args[2] (SELECT() || UNION())
                    OP($op, args = args)
                else
                    OP($op, args[1], FUN("", args = args[2:end]))
                end
            end
        end
    end
end

translate(::Val{Symbol("is null")}, n::FunctionNode, ctx) =
    OP(:IS, SQLClause[translate(arg, ctx) for arg in n.args]..., missing)

translate(::Val{Symbol("is not null")}, n::FunctionNode, ctx) =
    OP(:IS, SQLClause[translate(arg, ctx) for arg in n.args]..., OP(:NOT, missing))

translate(::Val{:case}, n::FunctionNode, ctx) =
    CASE(args = SQLClause[translate(arg, ctx) for arg in n.args])

for (name, op) in (("between", "BETWEEN"), ("not between", "NOT BETWEEN"))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, ctx)
            if length(n.args) == 3
                args = SQLClause[translate(arg, ctx) for arg in n.args]
                OP($op, args[1], args[2], args[3] |> KW(:AND))
            else
                translate_default(n, ctx)
            end
        end
    end
end

for (name, op) in (("current_date", "CURRENT_DATE"),
                   ("current_timestamp", "CURRENT_TIMESTAMP"))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, ctx)
            if isempty(n.args)
                OP($op)
            else
                translate_default(n, ctx)
            end
        end
    end
end

translate(n::LiteralNode, ctx) =
    LIT(n.val)

translate(n::SortNode, ctx) =
    SORT(over = translate(n.over, ctx), value = n.value, nulls = n.nulls)

function translate(n::VariableNode, ctx)
    c = get(ctx.vars, n.name, nothing)
    if c === nothing
        c = VAR(n.name)
    end
    c
end

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

struct Assemblage
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
end

assemble(n::SQLNode, ctx::TranslateContext) =
    assemble(n[], ctx)

function assemble(n::BoxNode, ctx::TranslateContext)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = assemble(n.over, ctx, refs′)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    Assemblage(res.clause, repl′)
end

assemble(n::SQLNode, ctx::TranslateContext, refs::Vector{SQLNode}) =
    assemble(n[], ctx, refs)

function assemble(::Nothing, ctx::TranslateContext, refs::Vector{SQLNode})
    @assert isempty(refs)
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    Assemblage(c, repl)
end

function assemble(n::AppendNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    as = allocate_alias(ctx, n.over)
    results = [as => base_res]
    for l in n.list
        res = assemble(l, ctx)
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
    Assemblage(c, repl)
end

function assemble(n::AsNode, ctx::TranslateContext, refs::Vector{SQLNode})
    res = assemble(n.over, ctx)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect ref over |> NameBound()
            @assert over !== nothing
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    Assemblage(res.clause, repl′)
end

function assemble(n::BindNode, ctx::TranslateContext, refs::Vector{SQLNode})
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.list[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    assemble(n.over, ctx′)
end

function assemble(n::DefineNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    tr_cache = Dict{Symbol, SQLClause}()
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            c = get!(tr_cache, name) do
                col = n.list[n.label_map[name]]
                translate(col, ctx, subs)
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
    Assemblage(c, repl)
end

function assemble(n::ExtendedJoinNode, ctx::TranslateContext, refs::Vector{SQLNode})
    left_res = assemble(n.over, ctx)
    left_as = allocate_alias(ctx, n.over)
    lateral = !isempty(n.lateral)
    if lateral
        lsubs = Dict{SQLNode, SQLClause}()
        for ref in n.lateral
            name = left_res.repl[ref]
            lsubs[ref] = ID(over = left_as, name = name)
        end
        right_res = assemble(n.joinee, TranslateContext(ctx, subs = lsubs))
    else
        right_res = assemble(n.joinee, ctx)
    end
    right_as = allocate_alias(ctx, n.joinee)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in left_res.repl
        subs[ref] = ID(over = left_as, name = name)
    end
    for (ref, name) in right_res.repl
        subs[ref] = ID(over = right_as, name = name)
    end
    on = translate(n.on, ctx, subs)
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
    Assemblage(c, repl)
end


function assemble(n::FromNode, ctx::TranslateContext, refs::Vector{SQLNode})
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
    Assemblage(c, repl)
end

function assemble(n::GroupNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    by = SQLClause[]
    tr_cache = Dict{Symbol, SQLClause}()
    for (name, i) in n.label_map
        key = n.by[i]
        ckey = translate(key, ctx, subs)
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
            c = translate(ref, ctx, subs)
            push!(trns, ref => c)
            has_aggregates = true
        end
    end
    if !has_keys && !has_aggregates
        return assemble(nothing, ctx, refs)
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
    Assemblage(c, repl)
end

assemble(n::HighlightNode, ctx::TranslateContext, ::Vector{SQLNode}) =
    assemble(n.over, ctx)

function assemble(n::LimitNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
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
    Assemblage(c, repl)
end

function assemble(n::OrderNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    by = translate(n.by, ctx, subs)
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
    Assemblage(c, repl)
end

function assemble(n::PartitionNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    ctx′ = TranslateContext(ctx, subs = subs)
    by = translate(n.by, ctx′)
    order_by = translate(n.order_by, ctx′)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if @dissect ref (nothing |> Agg(name = name))
            c = partition |> translate(ref, ctx′)
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
    Assemblage(c, repl)
end

function assemble(n::SelectNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    list = SQLClause[]
    for (name, i) in n.label_map
        col = n.list[i]
        c = translate(col, ctx, subs)
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
    Assemblage(c, repl)
end

function assemble(n::WhereNode, ctx::TranslateContext, refs::Vector{SQLNode})
    base_res = assemble(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    condition = translate(n.condition, ctx, subs)
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
    Assemblage(c, repl)
end

