# Translating a SQL node graph to a SQL statement.

function render(n; dialect = :default)
    actx = AnnotateContext()
    n′ = annotate(convert(SQLNode, n), actx)
    resolve!(actx)
    link!(actx)
    tctx = TranslateContext(dialect, actx.path_map)
    c = translate(n′, tctx)
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


# Translating scalar nodes.

function translate(n, ctx::TranslateContext, subs::Dict{SQLNode, SQLClause})
    ctx′ = TranslateContext(ctx, subs = subs)
    translate(n, ctx′)
end

function translate(n::SQLNode, ctx)
    c = get(ctx.subs, n, nothing)
    if c === nothing
        c = convert(SQLClause, translate(n[], ctx))
    end
    c
end

translate(ns::Vector{SQLNode}, ctx) =
    SQLClause[translate(n, ctx) for n in ns]

translate(::Nothing, ctx) =
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

function translate(n::ExtendedBindNode, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.list[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    translate(n.over, ctx′)
end

function translate(n::BoxNode, ctx)
    res = assemble(n, ctx)
    complete(res)
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
            elseif length(args) == 2 && (@dissect args[1] LIT(val = val)) && val == $default
                args[2]
            elseif (@dissect args[1] OP(name = name, args = args′)) && name === $(QuoteNode(op))
                OP($(QuoteNode(op)), args = SQLClause[args′..., args[2:end]...])
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


# Translating subquery nodes.

struct Assemblage
    clause::Union{SQLClause, Nothing}
    cols::OrderedDict{Symbol, SQLClause}
    repl::Dict{SQLNode, Symbol}

    Assemblage(clause; cols = OrderedDict{Symbol, SQLClause}(), repl = Dict{SQLNode, Symbol}()) =
        new(clause, cols, repl)
end

function complete(cols::OrderedDict{Symbol, SQLClause})
    list = SQLClause[]
    for (name, c) in cols
        if !((@dissect c ID(name = id_name)) && id_name == name)
            c = AS(over = c, name = name)
        end
        push!(list, c)
    end
    if isempty(list)
        push!(list, LIT(missing))
    end
    list
end

function complete(res::Assemblage)
    clause = res.clause
    if !(@dissect clause SELECT() || UNION())
        list = complete(res.cols)
        clause = SELECT(over = clause, list = list)
    else
        @assert isempty(res.cols)
    end
    @assert clause !== nothing
    clause
end

function make_subs(base::Assemblage, ::Nothing)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base.repl
        subs[ref] = base.cols[name]
    end
    subs
end

function make_subs(base::Assemblage, base_as::Symbol)
    subs = Dict{SQLNode, SQLClause}()
    base_cache = Dict{Symbol, SQLClause}()
    for (ref, name) in base.repl
        subs[ref] = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
    end
    subs
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

function make_repl(trns::Vector{Pair{SQLNode, SQLClause}})::Tuple{Dict{SQLNode, Symbol}, OrderedDict{Symbol, SQLClause}}
    repl = Dict{SQLNode, Symbol}()
    cols = OrderedDict{Symbol, SQLClause}()
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
        cols[name′] = c
        dups[name′] = 1
        renames[name, c] = name′
        repl[ref] = name′
    end
    (repl, cols)
end

assemble(n::SQLNode, ctx) =
    assemble(n[], ctx)

function assemble(n::BoxNode, ctx)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = assemble(n.over, refs′, ctx)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    Assemblage(res.clause, cols = res.cols, repl = repl′)
end

assemble(n::SQLNode, refs, ctx) =
    assemble(n[], refs, ctx)

function assemble(::Nothing, refs, ctx)
    @assert isempty(refs)
    Assemblage(nothing)
end

function assemble(n::AppendNode, refs, ctx)
    base = assemble(n.over, ctx)
    results = [n.over => base]
    for l in n.list
        res = assemble(l, ctx)
        push!(results, l => res)
    end
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in refs
        name = base.repl[ref]
        if name in keys(seen)
            other_ref = seen[name]
            if all(res.repl[ref] === res.repl[other_ref] for (l, res) in results)
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
    for (l, res) in results
        if !(@dissect res.clause (SELECT() || UNION()))
            as = nothing
            tail = res.clause
        else
            as = allocate_alias(ctx, l)
            tail = FROM(AS(over = complete(res), name = as))
        end
        subs = make_subs(res, as)
        cols = OrderedDict{Symbol, SQLClause}()
        for ref in refs
            !(ref in keys(dups)) || continue
            name = repl[ref]
            cols[name] = subs[ref]
        end
        c = SELECT(over = tail, list = complete(cols))
        push!(cs, c)
    end
    c = UNION(over = cs[1], all = true, list = cs[2:end])
    Assemblage(c, repl = repl)
end

function assemble(n::AsNode, refs, ctx)
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
    Assemblage(res.clause, cols = res.cols, repl = repl′)
end

function assemble(n::ExtendedBindNode, refs, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.list[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    assemble(n.over, ctx′)
end

function assemble(n::DefineNode, refs, ctx)
    base = assemble(n.over, ctx)
    if !any(ref -> (@dissect ref Get(name = name)) && name in keys(n.label_map), refs)
        return base
    end
    if !(@dissect base.clause (SELECT() || UNION()))
        base_as = nothing
        c = base.clause
    else
        base_as = allocate_alias(ctx, n.over)
        c = FROM(AS(over = complete(base), name = base_as))
    end
    subs = make_subs(base, base_as)
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    tr_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            col = get!(tr_cache, name) do
                def = n.list[n.label_map[name]]
                translate(def, ctx, subs)
            end
            push!(trns, ref => col)
        else
            push!(trns, ref => subs[ref])
        end
    end
    repl, cols = make_repl(trns)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::ExtendedJoinNode, refs, ctx)
    left = assemble(n.over, ctx)
    if @dissect left.clause (tail := FROM() || JOIN())
        left_as = nothing
    else
        left_as = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(left), name = left_as))
    end
    lateral = !isempty(n.lateral)
    subs = make_subs(left, left_as)
    if lateral
        right = assemble(n.joinee, TranslateContext(ctx, subs = subs))
    else
        right = assemble(n.joinee, ctx)
    end
    if @dissect right.clause ((joinee := nothing |> ID() |> AS(name = right_as)) |> FROM())
    else
        right_as = allocate_alias(ctx, n.joinee)
        joinee = AS(over = complete(right), name = right_as)
    end
    right_cache = Dict{Symbol, SQLClause}()
    for (ref, name) in right.repl
        subs[ref] = get(right_cache, name) do
            ID(over = right_as, name = name)
        end
    end
    on = translate(n.on, ctx, subs)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl(trns)
    c = JOIN(over = tail, joinee = joinee, on = on, left = n.left, right = n.right, lateral = lateral)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::FromNode, refs, ctx)
    output_columns = Set{Symbol}()
    for ref in refs
        match = @dissect ref (nothing |> Get(name = name))
        @assert match && name in n.table.column_set
        if !(name in output_columns)
            push!(output_columns, name)
        end
    end
    as = allocate_alias(ctx, n.table.name)
    cols = OrderedDict{Symbol, SQLClause}()
    for col in n.table.columns
        col in output_columns || continue
        cols[col] = ID(over = as, name = col)
    end
    tbl = ID(over = n.table.schema, name = n.table.name)
    c = FROM(AS(over = tbl, name = as))
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect ref (nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::GroupNode, refs, ctx)
    has_aggregates = any(ref -> (@dissect ref Agg()), refs)
    if isempty(n.by) && !has_aggregates
        return assemble(nothing, refs, ctx)
    end
    base = assemble(n.over, ctx)
    if @dissect base.clause (tail := nothing || FROM() || JOIN() || WHERE())
        base_as = nothing
    else
        base_as = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_as))
    end
    subs = make_subs(base, base_as)
    by = translate(n.by, ctx, subs)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if @dissect ref (nothing |> Get(name = name))
            @assert name in keys(n.label_map)
            ckey = by[n.label_map[name]]
            push!(trns, ref => ckey)
        elseif @dissect ref (nothing |> Agg(name = name))
            c = translate(ref, ctx, subs)
            push!(trns, ref => c)
        end
    end
    repl, cols = make_repl(trns)
    @assert !isempty(cols)
    if has_aggregates
        c = GROUP(over = tail, by = by)
        return Assemblage(c, cols = cols, repl = repl)
    else
        list = complete(cols)
        c = SELECT(over = tail, distinct = true, list = list)
        return Assemblage(c, repl = repl)
    end
end

assemble(n::HighlightNode, refs, ctx) =
    assemble(n.over, ctx)

function assemble(n::LimitNode, refs, ctx)
    base = assemble(n.over, ctx)
    if n.offset === nothing && n.limit === nothing
        return base
    end
    if @dissect base.clause (tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING() || ORDER())
        base_as = nothing
    else
        base_as = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_as))
    end
    subs = make_subs(base, base_as)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl(trns)
    c = LIMIT(over = tail, offset = n.offset, limit = n.limit)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::OrderNode, refs, ctx)
    base = assemble(n.over, ctx)
    if isempty(n.by)
        return base
    end
    if @dissect base.clause (tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_as = nothing
    else
        tail = FROM(AS(over = complete(base), name = base_as))
        base_as = allocate_alias(ctx, n.over)
    end
    subs = make_subs(base, base_as)
    by = translate(n.by, ctx, subs)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl(trns)
    c = ORDER(over = tail, by = by)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::PartitionNode, refs, ctx)
    base = assemble(n.over, ctx)
    if !any(ref -> (@dissect ref Agg()), refs)
        return base
    end
    if @dissect base.clause (tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_as = nothing
    else
        base_as = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_as))
    end
    subs = make_subs(base, base_as)
    ctx′ = TranslateContext(ctx, subs = subs)
    by = translate(n.by, ctx′)
    order_by = translate(n.order_by, ctx′)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if @dissect ref (nothing |> Agg(name = name))
            c = partition |> translate(ref, ctx′)
            push!(trns, ref => c)
        else
            push!(trns, ref => subs[ref])
        end
    end
    repl, cols = make_repl(trns)
    c = WINDOW(over = tail, list = [])
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::SelectNode, refs, ctx)
    base = assemble(n.over, ctx)
    if !(@dissect base.clause (SELECT() || UNION()))
        base_as = nothing
        tail = base.clause
    else
        base_as = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_as))
    end
    subs = make_subs(base, base_as)
    cols = OrderedDict{Symbol, SQLClause}()
    for (name, i) in n.label_map
        col = n.list[i]
        cols[name] = translate(col, ctx, subs)
    end
    c = SELECT(over = tail, list = complete(cols))
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        ref_name = nothing
        @dissect ref (nothing |> Get(name = name))
        @assert name !== nothing
        repl[ref] = name
    end
    Assemblage(c, repl = repl)
end

function merge_conditions(c1, c2)
    if @dissect c1 OP(name = :AND, args = args1)
        if @dissect c2 OP(name = :AND, args = args2)
            return OP(:AND, args1..., args2...)
        else
            return OP(:AND, args1..., c2)
        end
    elseif @dissect c2 OP(name = :AND, args = args2)
        return OP(:AND, c1, args2...)
    else
        return OP(:AND, c1, c2)
    end
end

function assemble(n::WhereNode, refs, ctx)
    base = assemble(n.over, ctx)
    if (@dissect base.clause (nothing || FROM() || JOIN() || WHERE() || HAVING())) ||
       (@dissect base.clause GROUP(by = by)) && !isempty(by)
        subs = make_subs(base, nothing)
        condition = translate(n.condition, ctx, subs)
        if (@dissect condition LIT(val = val)) && val === true
            return base
        end
        if @dissect base.clause tail |> WHERE(condition = tail_condition)
            condition = merge_conditions(tail_condition, condition)
            c = WHERE(over = tail, condition = condition)
        elseif @dissect base.clause GROUP()
            c = HAVING(over = base.clause, condition = condition)
        elseif @dissect base.clause tail |> HAVING(condition = tail_condition)
            condition = merge_conditions(tail_condition, condition)
            c = HAVING(over = tail, condition = condition)
        else
            c = WHERE(over = base.clause, condition = condition)
        end
    else
        base_as = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_as))
        subs = make_subs(base, base_as)
        condition = translate(n.condition, ctx, subs)
        if (@dissect condition LIT(val = val)) && val === true
            return base
        end
        c = WHERE(over = tail, condition = condition)
    end
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl(trns)
    return Assemblage(c, cols = cols, repl = repl)
end

