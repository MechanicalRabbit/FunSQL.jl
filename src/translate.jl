# Translating a SQL node graph to a SQL statement.

# Partially constructed query.

struct Assemblage
    name::Symbol                            # Base name for the alias.
    clause::Union{SQLClause, Nothing}       # A SQL subquery (possibly without SELECT clause).
    cols::OrderedDict{Symbol, SQLClause}    # SELECT arguments, if necessary.
    repl::Dict{SQLNode, Symbol}             # Maps a reference node to a column alias.

    Assemblage(name, clause; cols = OrderedDict{Symbol, SQLClause}(), repl = Dict{SQLNode, Symbol}()) =
        new(name, clause, cols, repl)
end

# Pack SELECT arguments.
function complete(cols::OrderedDict{Symbol, SQLClause})
    args = SQLClause[]
    for (name, col) in cols
        if !(@dissect(col, ID(name = id_name)) && id_name == name)
            col = AS(over = col, name = name)
        end
        push!(args, col)
    end
    if isempty(args)
        push!(args, AS(over = LIT(missing), name = :_))
    end
    args
end

# Add a SELECT clause to a partially assembled subquery (if necessary).
function complete(a::Assemblage)
    clause = a.clause
    if !@dissect(clause, SELECT() || UNION())
        args = complete(a.cols)
        clause = SELECT(over = clause, args = args)
    end
    @assert clause !== nothing
    clause
end

# Build node->clause map assuming that the assemblage will be extended.
function make_subs(a::Assemblage, ::Nothing)::Dict{SQLNode, SQLClause}
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in a.repl
        subs[ref] = a.cols[name]
    end
    subs
end

# Build node->clause map assuming that the assemblage will be completed.
function make_subs(a::Assemblage, alias::Symbol)
    subs = Dict{SQLNode, SQLClause}()
    cache = Dict{Symbol, SQLClause}()
    for (ref, name) in a.repl
        subs[ref] = get(cache, name) do
            ID(over = alias, name = name)
        end
    end
    subs
end

# Build a node->alias map and implicit SELECT columns for a UNION query.
function make_repl_cols(refs::Vector{SQLNode})::Tuple{Dict{SQLNode, Symbol}, OrderedDict{Symbol, SQLClause}}
    repl = Dict{SQLNode, Symbol}()
    cols = OrderedDict{Symbol, SQLClause}()
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
        repl[ref] = name′
        cols[name′] = ID(name′)
        dups[name′] = 1
    end
    repl, cols
end

# Build a node->alias map and SELECT columns.
function make_repl_cols(trns::Vector{Pair{SQLNode, SQLClause}})::Tuple{Dict{SQLNode, Symbol}, OrderedDict{Symbol, SQLClause}}
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

function aligned_columns(refs, repl, args)
    length(refs) == length(args) || return false
    for (ref, arg) in zip(refs, args)
        if !(@dissect(arg, ID(name = name) || AS(name = name)) && name === repl[ref])
            return false
        end
    end
    return true
end

struct CTEAssemblage
    a::Assemblage
    name::Symbol
    qualifiers::Vector{Symbol}
    materialized::Union{Bool, Nothing}
    external::Bool

    CTEAssemblage(a; name, qualifiers = Symbol[], materialized = nothing, external = false) =
        new(a, name, qualifiers, materialized, external)
end


# Translating context.

struct TranslateContext
    dialect::SQLDialect
    defs::Vector{SQLNode}
    aliases::Dict{Symbol, Int}
    ctes::Vector{CTEAssemblage}
    cte_map::Dict{Symbol, Int}
    knot::Ref{Int}
    recursive::Ref{Bool}
    refs::Vector{SQLNode}
    vars::Dict{Symbol, SQLClause}
    subs::Dict{SQLNode, SQLClause}

    TranslateContext(; dialect, defs) =
        new(dialect,
            defs,
            Dict{Symbol, Int}(),
            CTEAssemblage[],
            Dict{Symbol, Int}(),
            Ref(0),
            Ref(false),
            SQLNode[],
            Dict{Symbol, SQLClause}(),
            Dict{Int, SQLClause}())

    function TranslateContext(ctx::TranslateContext; refs = missing, vars = missing, subs = missing)
        new(ctx.dialect,
            ctx.defs,
            ctx.aliases,
            ctx.ctes,
            ctx.cte_map,
            ctx.knot,
            ctx.recursive,
            coalesce(refs, ctx.refs),
            coalesce(vars, ctx.vars),
            coalesce(subs, ctx.subs))
    end
end

allocate_alias(ctx::TranslateContext, a::Assemblage) =
    allocate_alias(ctx, a.name)

function allocate_alias(ctx::TranslateContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

function translate(n::SQLNode)
    @dissect(n, WithContext(over = n′, dialect = dialect, defs = defs)) || throw(IllFormedError())
    ctx = TranslateContext(dialect = dialect, defs = defs)
    c = translate(n′, ctx)
    with_args = SQLClause[]
    for cte_a in ctx.ctes
        !cte_a.external || continue
        cols = Symbol[name for name in keys(cte_a.a.cols)]
        if isempty(cols)
            push!(cols, :_)
        end
        over = complete(cte_a.a)
        materialized = cte_a.materialized
        if materialized !== nothing
            over = NOTE(materialized ? "MATERIALIZED" : "NOT MATERIALIZED", over = over)
        end
        arg = AS(name = cte_a.name, columns = cols, over = over)
        push!(with_args, arg)
    end
    if !isempty(with_args)
        c = WITH(over = c, args = with_args, recursive = ctx.recursive[])
    end
    WITH_CONTEXT(over = c, dialect = ctx.dialect)
end

function translate(n::SQLNode, ctx)
    c = get(ctx.subs, n, nothing)
    if c === nothing
        c = convert(SQLClause, translate(n[], ctx))
    end
    c
end

function translate(ns::Vector{SQLNode}, ctx)
    SQLClause[translate(n, ctx) for n in ns]
end

translate(::Nothing, ctx) =
    nothing

function translate(n, ctx::TranslateContext, subs::Dict{SQLNode, SQLClause})
    ctx′ = TranslateContext(ctx, subs = subs)
    translate(n, ctx′)
end

function translate(n::AggregateNode, ctx)
    args = translate(n.args, ctx)
    filter = translate(n.filter, ctx)
    AGG(n.name, args = args, filter = filter)
end

function translate(n::AsNode, ctx)
    translate(n.over, ctx)
end

function translate(n::BindNode, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.args[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    translate(n.over, ctx′)
end

function translate(n::LinkedNode, ctx)
    base = assemble(n.over, TranslateContext(ctx, refs = n.refs))
    complete(base)
end

function translate(n::FunctionNode, ctx)
    args = translate(n.args, ctx)
    if n.name === :and
        args′ = SQLClause[]
        for arg in args
            if @dissect(arg, LIT(val = true))
            elseif @dissect(arg, FUN(name = :and, args = args′′))
                append!(args′, args′′)
            else
                push!(args′, arg)
            end
        end
        args = args′
        if isempty(args)
            return LIT(true)
        elseif length(args) == 1
            return args[1]
        end
    elseif n.name === :or
        args′ = SQLClause[]
        for arg in args
            if @dissect(arg, LIT(val = false))
            elseif @dissect(arg, FUN(name = :or, args = args′′))
                append!(args′, args′′)
            else
                push!(args′, arg)
            end
        end
        args = args′
        if isempty(args)
            return LIT(false)
        elseif length(args) == 1
            return args[1]
        end
    elseif n.name === :not
        if length(args) == 1 && @dissect(args[1], LIT(val = val)) && val isa Bool
            return LIT(!val)
        end
    end
    FUN(name = n.name, args = args)
end

function translate(n::IsolatedNode, ctx)
    base = assemble(ctx.defs[n.idx], ctx)
    complete(base)
end

function translate(n::LiteralNode, ctx)
    LIT(n.val)
end

function translate(n::ResolvedNode, ctx)
    translate(n.over, ctx)
end

translate(n::SortNode, ctx) =
    SORT(over = translate(n.over, ctx), value = n.value, nulls = n.nulls)

function translate(n::VariableNode, ctx)
    c = get(ctx.vars, n.name, nothing)
    if c === nothing
        c = VAR(n.name)
    end
    c
end

function assemble(n::SQLNode, ctx)
    assemble(n[], ctx)
end

function assemble(::Nothing, ctx)
    @assert isempty(ctx.refs)
    Assemblage(:_, nothing)
end

function assemble(n::AppendNode, ctx)
    base = assemble(n.over, ctx)
    branches = [n.over => base]
    for arg in n.args
        push!(branches, arg => assemble(arg, ctx))
    end
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in ctx.refs
        name = base.repl[ref]
        if name in keys(seen)
            other_ref = seen[name]
            other_ref !== ref || continue
            if all(a.repl[ref] === a.repl[other_ref] for (arg, a) in branches)
                dups[ref] = seen[name]
            end
        else
            seen[name] = ref
        end
    end
    urefs = SQLNode[]
    for ref in ctx.refs
        if !(ref in keys(dups))
            push!(urefs, ref)
            dups[ref] = ref
        end
    end
    repl, dummy_cols = make_repl_cols(urefs)
    for (ref, uref) in dups
        repl[ref] = repl[uref]
    end
    a_name = base.name
    cs = SQLClause[]
    for (arg, a) in branches
        if a.name !== a_name
            a_name = :union
        end
        if @dissect(a.clause, SELECT(args = args)) && aligned_columns(urefs, repl, args)
            push!(cs, a.clause)
            continue
        elseif !@dissect(a.clause, SELECT() || UNION())
            alias = nothing
            tail = a.clause
        else
            alias = allocate_alias(ctx, a)
            tail = FROM(AS(over = complete(a), name = alias))
        end
        subs = make_subs(a, alias)
        cols = OrderedDict{Symbol, SQLClause}()
        for ref in urefs
            name = repl[ref]
            cols[name] = subs[ref]
        end
        c = SELECT(over = tail, args = complete(cols))
        push!(cs, c)
    end
    c = UNION(over = cs[1], all = true, args = cs[2:end])
    Assemblage(a_name, c, repl = repl, cols = dummy_cols)
end

function assemble(n::AsNode, ctx)
    refs′ = SQLNode[]
    for ref in ctx.refs
        if @dissect(ref, over |> Bound())
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    base = assemble(n.over, TranslateContext(ctx, refs = refs′))
    repl′ = Dict{SQLNode, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, over |> Bound())
            repl′[ref] = base.repl[over]
        else
            repl′[ref] = base.repl[ref]
        end
    end
    Assemblage(n.name, base.clause, cols = base.cols, repl = repl′)
end

function assemble(n::BindNode, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.args[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    assemble(n.over, ctx′)
end

function assemble(n::DefineNode, ctx)
    base = assemble(n.over, ctx)
    if !@dissect(base.clause, SELECT() || UNION())
        base_alias = nothing
        c = base.clause
    else
        base_alias = allocate_alias(ctx, base)
        c = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    tr_cache = Dict{Symbol, SQLClause}()
    for (f, i) in n.label_map
        tr_cache[f] = translate(n.args[i], ctx, subs)
    end
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = name)) && name in keys(tr_cache)
            push!(trns, ref => tr_cache[name])
        else
            push!(trns, ref => subs[ref])
        end
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::FromFunctionNode, ctx)
    seen = Set{Symbol}()
    column_set = Set(n.columns)
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = name)) && name in column_set || error()
        if !(name in seen)
            push!(seen, name)
        end
    end
    over = translate(n.over, ctx)
    alias = allocate_alias(ctx, label(n.over))
    c = FROM(AS(over = over, name = alias, columns = n.columns))
    cols = OrderedDict{Symbol, SQLClause}()
    for col in n.columns
        col in seen || continue
        cols[col] = ID(over = alias, name = col)
    end
    repl = Dict{SQLNode, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    Assemblage(label(n.over), c, cols = cols, repl = repl)
end

function assemble(n::FromKnotNode, ctx)
    cte_a = ctx.ctes[ctx.knot[]]
    name = cte_a.a.name
    alias = allocate_alias(ctx, name)
    tbl = ID(cte_a.qualifiers, cte_a.name)
    c = FROM(AS(over = tbl, name = alias))
    subs = make_subs(cte_a.a, alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(name, c, cols = cols, repl = repl)
end

assemble(::FromNothingNode, ctx) =
    assemble(nothing, ctx)

function unwrap_repl(a::Assemblage)
    repl′ = Dict{SQLNode, Symbol}()
    for (ref, name) in a.repl
        @dissect(ref, over |> Bound()) || error()
        repl′[over] = name
    end
    Assemblage(a.name, a.clause, cols = a.cols, repl = repl′)
end

function assemble(n::FromReferenceNode, ctx)
    cte_a = ctx.ctes[ctx.cte_map[n.name]]
    alias = allocate_alias(ctx, n.name)
    tbl = ID(cte_a.qualifiers, cte_a.name)
    c = FROM(AS(over = tbl, name = alias))
    subs = make_subs(unwrap_repl(cte_a.a), alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(n.name, c, cols = cols, repl = repl)
end

function assemble(n::FromTableNode, ctx)
    seen = Set{Symbol}()
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = name)) && name in n.table.column_set || error()
        if !(name in seen)
            push!(seen, name)
        end
    end
    alias = allocate_alias(ctx, n.table.name)
    tbl = ID(n.table.qualifiers, n.table.name)
    c = FROM(AS(over = tbl, name = alias))
    cols = OrderedDict{Symbol, SQLClause}()
    for col in n.table.columns
        col in seen || continue
        cols[col] = ID(over = alias, name = col)
    end
    repl = Dict{SQLNode, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    Assemblage(n.table.name, c, cols = cols, repl = repl)
end

function assemble(n::FromValuesNode, ctx)
    columns = Symbol[fieldnames(typeof(n.columns))...]
    column_set = Set{Symbol}(columns)
    seen = Set{Symbol}()
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = name)) && name in column_set || error()
        if !(name in seen)
            push!(seen, name)
        end
    end
    if length(seen) == length(n.columns)
        rows = Tables.rowtable(n.columns)
        column_aliases = columns
    elseif !isempty(seen)
        rows = Tables.rowtable(NamedTuple([(k, v) for (k, v) in pairs(n.columns) if k in seen]))
        column_aliases = filter(in(seen), columns)
    else
        rows = fill((; _ = missing), length(n.columns[1]))
        column_aliases = [:_]
    end
    alias = allocate_alias(ctx, :values)
    cols = OrderedDict{Symbol, SQLClause}()
    if isempty(rows)
        c = WHERE(false)
        for col in columns
            col in seen || continue
            cols[col] = LIT(missing)
        end
    elseif ctx.dialect.has_as_columns
        c = FROM(AS(alias, columns = column_aliases, over = VALUES(rows)))
        for col in columns
            col in seen || continue
            cols[col] = ID(over = alias, name = col)
        end
    else
        column_prefix = ctx.dialect.values_column_prefix
        column_index = ctx.dialect.values_column_index
        column_prefix !== nothing || error()
        c = FROM(AS(alias, over = VALUES(rows)))
        for col in columns
            col in seen || continue
            name = Symbol(column_prefix, column_index)
            cols[col] = ID(over = alias, name = name)
            column_index += 1
        end
    end
    repl = Dict{SQLNode, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    Assemblage(:values, c, cols = cols, repl = repl)
end

function assemble(n::GroupNode, ctx)
    has_aggregates = any(ref -> @dissect(ref, Agg() || Agg() |> Bound()), ctx.refs)
    if isempty(n.by) && !has_aggregates
        return assemble(nothing, ctx)
    end
    base = assemble(n.over, ctx)
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    by = SQLClause[subs[key] for key in n.by]
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = name))
            @assert name in keys(n.label_map)
            push!(trns, ref => by[n.label_map[name]])
        elseif @dissect(ref, nothing |> Agg())
            push!(trns, ref => translate(ref, ctx, subs))
        elseif @dissect(ref, (over := nothing |> Agg()) |> Bound())
            push!(trns, ref => translate(over, ctx, subs))
        end
    end
    if !has_aggregates
        for name in keys(n.label_map)
            push!(trns, Get(name = name) => by[n.label_map[name]])
        end
    end
    repl, cols = make_repl_cols(trns)
    @assert !isempty(cols)
    if has_aggregates
        c = GROUP(over = tail, by = by)
    else
        args = complete(cols)
        c = SELECT(over = tail, distinct = true, args = args)
        cols = OrderedDict{Symbol, SQLClause}([name => ID(name) for name in keys(cols)])
    end
    return Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::IntAutoDefineNode, ctx)
    base = assemble(n.over, ctx)
    if isempty(ctx.refs)
        return base
    end
    if !@dissect(base.clause, SELECT() || UNION())
        base_alias = nothing
        c = base.clause
    else
        base_alias = allocate_alias(ctx, base)
        c = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => translate(ref, ctx, subs))
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::IntJoinNode, ctx)
    left = assemble(n.over, ctx)
    if @dissect(left.clause, tail := FROM() || JOIN())
        left_alias = nothing
    else
        left_alias = allocate_alias(ctx, left)
        tail = FROM(AS(over = complete(left), name = left_alias))
    end
    lateral = n.lateral
    subs = make_subs(left, left_alias)
    if lateral
        right = assemble(n.joinee, TranslateContext(ctx, subs = subs))
    else
        right = assemble(n.joinee, ctx)
    end
    if @dissect(right.clause, (joinee := (nothing || nothing |> ID()) |> ID() |> AS(name = right_alias, columns = nothing)) |> FROM()) ||
       @dissect(right.clause, (joinee := nothing |> ID(name = right_alias)) |> FROM()) ||
       @dissect(right.clause, (joinee := FUN() |> AS(name = right_alias)) |> FROM())
        for (ref, name) in right.repl
            subs[ref] = right.cols[name]
        end
        if ctx.dialect.has_implicit_lateral
            lateral = false
        end
    else
        right_alias = allocate_alias(ctx, right)
        joinee = AS(over = complete(right), name = right_alias)
        right_cache = Dict{Symbol, SQLClause}()
        for (ref, name) in right.repl
            subs[ref] = get(right_cache, name) do
                ID(over = right_alias, name = name)
            end
        end
    end
    on = translate(n.on, ctx, subs)
    c = JOIN(over = tail, joinee = joinee, on = on, left = n.left, right = n.right, lateral = lateral)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(left.name, c, cols = cols, repl = repl)
end

function assemble(n::IterateNode, ctx)
    ctx′ = TranslateContext(ctx, vars = Dict{Symbol, SQLClause}())
    left = assemble(n.over, ctx)
    repl = Dict{SQLNode, Symbol}()
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in ctx.refs
        !in(ref, keys(repl)) || continue
        name = left.repl[ref]
        repl[ref] = name
        if name in keys(seen)
            dups[ref] = seen[name]
        else
            seen[name] = ref
        end
    end
    temp_union = Assemblage(label(n.iterator), left.clause, cols = left.cols, repl = repl)
    union_alias = allocate_alias(ctx, temp_union)
    cte = CTEAssemblage(temp_union, name = union_alias)
    push!(ctx.ctes, cte)
    knot = ctx.knot[] = lastindex(ctx.ctes)
    right = assemble(n.iterator, ctx)
    urefs = SQLNode[]
    for ref in ctx.refs
        !(ref in keys(dups)) || continue
        dups[ref] = ref
        push!(urefs, ref)
    end
    cs = SQLClause[]
    for (arg, a) in (n.over => left, n.iterator => right)
        if @dissect(a.clause, SELECT(args = args)) && aligned_columns(urefs, left.repl, args)
            push!(cs, a.clause)
            continue
        elseif !@dissect(a.clause, SELECT() || UNION())
            alias = nothing
            tail = a.clause
        else
            alias = allocate_alias(ctx, a)
            tail = FROM(AS(over = complete(a), name = alias))
        end
        subs = make_subs(a, alias)
        cols = OrderedDict{Symbol, SQLClause}()
        for ref in urefs
            name = left.repl[ref]
            cols[name] = subs[ref]
        end
        c = SELECT(over = tail, args = complete(cols))
        push!(cs, c)
    end
    union_clause = UNION(over = cs[1], all = true, args = cs[2:end])
    cols = OrderedDict{Symbol, SQLClause}()
    for ref in urefs
        name = left.repl[ref]
        cols[name] = ID(name)
    end
    union = Assemblage(right.name, union_clause, cols = cols, repl = repl)
    ctx.ctes[knot] = CTEAssemblage(union, name = union_alias)
    ctx.recursive[] = true
    alias = allocate_alias(ctx, union)
    c = FROM(AS(over = ID(union_alias), name = alias))
    subs = make_subs(union, alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(union.name, c, cols = cols, repl = repl)
end

function assemble(n::LimitNode, ctx)
    base = assemble(n.over, ctx)
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING() || ORDER())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    c = LIMIT(over = tail, offset = n.offset, limit = n.limit)
    subs = make_subs(base, base_alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::LinkedNode, ctx)
    a = assemble(n.over, TranslateContext(ctx, refs = n.refs))
    n.n_ext_refs < length(n.refs) || return a
    dups = Set{Symbol}()
    for (k, ref) in enumerate(n.refs)
        col = a.repl[ref]
        if col in dups
            if k > n.n_ext_refs
                alias = allocate_alias(ctx, a)
                c = FROM(AS(over = complete(a), name = alias))
                subs = make_subs(a, alias)
                trns = Pair{SQLNode, SQLClause}[]
                for ref in n.refs
                    push!(trns, ref => subs[ref])
                end
                repl, cols = make_repl_cols(trns)
                return Assemblage(a.name, c, cols = cols, repl = repl)
            end
        elseif !@dissect(a.cols[col], (nothing |> ID() || nothing |> ID() |> ID() || VAR() || LIT()))
            push!(dups, col)
        end
    end
    a
end

function assemble(n::OrderNode, ctx)
    base = assemble(n.over, ctx)
    @assert !isempty(n.by)
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    by = translate(n.by, ctx, subs)
    c = ORDER(over = tail, by = by)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::PartitionNode, ctx)
    base = assemble(n.over, ctx)
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    c = WINDOW(over = tail, args = [])
    subs = make_subs(base, base_alias)
    ctx′ = TranslateContext(ctx, subs = subs)
    by = translate(n.by, ctx′)
    order_by = translate(n.order_by, ctx′)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLNode, SQLClause}[]
    has_aggregates = false
    for ref in ctx.refs
        if @dissect(ref, nothing |> Agg()) && n.name === nothing
            push!(trns, ref => partition |> translate(ref, ctx′))
            has_aggregates = true
        elseif @dissect(ref, (over := nothing |> Agg()) |> Bound(name = name)) && name === n.name
            push!(trns, ref => partition |> translate(over, ctx′))
            has_aggregates = true
        else
            push!(trns, ref => subs[ref])
        end
    end
    @assert has_aggregates
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::SelectNode, ctx)
    base = assemble(n.over, ctx)
    if !@dissect(base.clause, SELECT() || UNION())
        base_alias = nothing
        tail = base.clause
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    cols = OrderedDict{Symbol, SQLClause}()
    for (name, i) in n.label_map
        col = n.args[i]
        cols[name] = translate(col, ctx, subs)
    end
    c = SELECT(over = tail, args = complete(cols))
    cols = OrderedDict{Symbol, SQLClause}([name => ID(name) for name in keys(cols)])
    repl = Dict{SQLNode, Symbol}()
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = name)) || error()
        repl[ref] = name
    end
    Assemblage(base.name, c, cols = cols, repl = repl)
end

function merge_conditions(c1, c2)
    if @dissect(c1, FUN(name = :and, args = args1))
        if @dissect(c2, FUN(name = :and, args = args2))
            return FUN(:and, args1..., args2...)
        else
            return FUN(:and, args1..., c2)
        end
    elseif @dissect(c2, FUN(name = :and, args = args2))
        return FUN(:and, c1, args2...)
    else
        return FUN(:and, c1, c2)
    end
end

function assemble(n::WhereNode, ctx)
    base = assemble(n.over, ctx)
    if @dissect(base.clause, nothing || FROM() || JOIN() || WHERE() || HAVING()) ||
       @dissect(base.clause, GROUP(by = by)) && !isempty(by)
        subs = make_subs(base, nothing)
        condition = translate(n.condition, ctx, subs)
        if @dissect(condition, LIT(val = true))
            return base
        end
        if @dissect(base.clause, tail |> WHERE(condition = tail_condition))
            condition = merge_conditions(tail_condition, condition)
            c = WHERE(over = tail, condition = condition)
        elseif @dissect(base.clause, GROUP())
            c = HAVING(over = base.clause, condition = condition)
        elseif @dissect(base.clause, tail |> HAVING(condition = tail_condition))
            condition = merge_conditions(tail_condition, condition)
            c = HAVING(over = tail, condition = condition)
        else
            c = WHERE(over = base.clause, condition = condition)
        end
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(over = complete(base), name = base_alias))
        subs = make_subs(base, base_alias)
        condition = translate(n.condition, ctx, subs)
        if @dissect(condition, LIT(val = true))
            return base
        end
        c = WHERE(over = tail, condition = condition)
    end
    trns = Pair{SQLNode, SQLClause}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(base.name, c, cols = cols, repl = repl)
end

function assemble(n::WithNode, ctx)
    ctx′ = TranslateContext(ctx, vars = Dict{Symbol, SQLClause}())
    for (name, i) in n.label_map
        a = assemble(n.args[i], ctx)
        alias = allocate_alias(ctx, a)
        cte = CTEAssemblage(a, name = alias, materialized = n.materialized)
        push!(ctx.ctes, cte)
        ctx.cte_map[name] = lastindex(ctx.ctes)
    end
    assemble(n.over, ctx)
end

function assemble(n::WithExternalNode, ctx)
    ctx′ = TranslateContext(ctx, vars = Dict{Symbol, SQLClause}())
    for (name, i) in n.label_map
        a = assemble(n.args[i], ctx)
        table_name = a.name
        table_columns = Symbol[column_name for column_name in keys(a.cols)]
        if isempty(table_columns)
            push!(table_columns, :_)
        end
        table = SQLTable(name = table_name, qualifiers = n.qualifiers, columns = table_columns)
        if n.handler !== nothing
            n.handler(table => complete(a))
        end
        cte = CTEAssemblage(a, name = table.name, qualifiers = table.qualifiers, external = true)
        push!(ctx.ctes, cte)
        ctx.cte_map[name] = lastindex(ctx.ctes)
    end
    assemble(n.over, ctx)
end
