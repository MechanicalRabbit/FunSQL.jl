# Translating a SQL node graph to a SQL syntax tree.

# Partially constructed query.

struct Assemblage
    name::Symbol                            # Base name for the alias.
    syntax::Union{SQLSyntax, Nothing}       # A SQL subquery (possibly without SELECT clause).
    cols::OrderedDict{Symbol, SQLSyntax}    # SELECT arguments, if necessary.
    repl::Dict{SQLQuery, Symbol}            # Maps a reference node to a column alias.

    Assemblage(name, syntax; cols = OrderedDict{Symbol, SQLSyntax}(), repl = Dict{SQLQuery, Symbol}()) =
        new(name, syntax, cols, repl)
end

# Pack SELECT arguments.
function complete(cols::OrderedDict{Symbol, SQLSyntax})
    args = SQLSyntax[]
    for (name, col) in cols
        if !(@dissect(col, ID(name = (local id_name))) && id_name == name)
            col = AS(tail = col, name = name)
        end
        push!(args, col)
    end
    if isempty(args)
        push!(args, AS(tail = LIT(missing), name = :_))
    end
    args
end

# Add a SELECT clause to a partially assembled subquery (if necessary).
function complete(a::Assemblage)
    syntax = a.syntax
    if !@dissect(syntax, SELECT() || UNION())
        args = complete(a.cols)
        syntax = SELECT(tail = syntax, args = args)
    end
    @assert syntax !== nothing
    syntax
end

# Add a SELECT clause aligned with the exported references.
function complete_aligned(a::Assemblage, ctx)
    aligned =
        length(a.cols) == length(ctx.refs) &&
        all(a.repl[ref] === name for (name, ref) in zip(keys(a.cols), ctx.refs))
    !aligned || return complete(a)
    if !@dissect(a.syntax, SELECT() || UNION())
        alias = nothing
        syntax = a.syntax
    else
        alias = allocate_alias(ctx, a)
        syntax = FROM(AS(tail = a.syntax, name = alias))
    end
    subs = make_subs(a, alias)
    repl = Dict{SQLQuery, Symbol}()
    cols = OrderedDict{Symbol, SQLSyntax}()
    for ref in ctx.refs
        name = repl[ref] = a.repl[ref]
        cols[name] = subs[ref]
    end
    a′ = Assemblage(a.name, syntax, repl = repl, cols = cols)
    complete(a′)
end

# Build node->syntax map assuming that the assemblage will be extended.
function make_subs(a::Assemblage, ::Nothing)::Dict{SQLQuery, SQLSyntax}
    subs = Dict{SQLQuery, SQLSyntax}()
    for (ref, name) in a.repl
        subs[ref] = a.cols[name]
    end
    subs
end

# Build node->syntax map assuming that the assemblage will be completed.
function make_subs(a::Assemblage, alias::Symbol)
    subs = Dict{SQLQuery, SQLSyntax}()
    cache = Dict{Symbol, SQLSyntax}()
    for (ref, name) in a.repl
        subs[ref] = get(cache, name) do
            ID(tail = alias, name = name)
        end
    end
    subs
end

# Build a node->alias map and implicit SELECT columns for a UNION query.
function make_repl_cols(refs::Vector{SQLQuery})::Tuple{Dict{SQLQuery, Symbol}, OrderedDict{Symbol, SQLSyntax}}
    repl = Dict{SQLQuery, Symbol}()
    cols = OrderedDict{Symbol, SQLSyntax}()
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
function make_repl_cols(trns::Vector{Pair{SQLQuery, SQLSyntax}})::Tuple{Dict{SQLQuery, Symbol}, OrderedDict{Symbol, SQLSyntax}}
    repl = Dict{SQLQuery, Symbol}()
    cols = OrderedDict{Symbol, SQLSyntax}()
    dups = Dict{Symbol, Int}()
    renames = Dict{Tuple{Symbol, SQLSyntax}, Symbol}()
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
        if !(@dissect(arg, ID(name = (local name)) || AS(name = (local name))) && name === repl[ref])
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
    catalog::SQLCatalog
    tail::Union{SQLQuery, Nothing}
    defs::Vector{SQLQuery}
    aliases::Dict{Symbol, Int}
    recursive::Ref{Bool}
    ctes::Vector{CTEAssemblage}
    cte_map::Base.ImmutableDict{Tuple{Symbol, Int}, Int}
    knot::Int
    refs::Vector{SQLQuery}
    vars::Base.ImmutableDict{Tuple{Symbol, Int}, SQLSyntax}
    subs::Dict{SQLQuery, SQLSyntax}

    TranslateContext(; catalog, defs) =
        new(catalog,
            nothing,
            defs,
            Dict{Symbol, Int}(),
            Ref(false),
            CTEAssemblage[],
            Base.ImmutableDict{Tuple{Symbol, Int}, Int}(),
            0,
            SQLQuery[],
            Base.ImmutableDict{Tuple{Symbol, Int}, SQLSyntax}(),
            Dict{Int, SQLSyntax}())

    function TranslateContext(ctx::TranslateContext; tail = ctx.tail, cte_map = ctx.cte_map, knot = ctx.knot, refs = ctx.refs, vars = ctx.vars, subs = ctx.subs)
        new(ctx.catalog,
            tail,
            ctx.defs,
            ctx.aliases,
            ctx.recursive,
            ctx.ctes,
            cte_map,
            knot,
            refs,
            vars,
            subs)
    end
end

allocate_alias(ctx::TranslateContext, a::Assemblage) =
    allocate_alias(ctx, a.name)

function allocate_alias(ctx::TranslateContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

function translate(q::SQLQuery)
    @dissect(q, (local q′) |> Linked(refs = (local refs)) |> WithContext(catalog = (local catalog), defs = (local defs))) || throw(IllFormedError())
    ctx = TranslateContext(catalog = catalog, defs = defs)
    ctx′ = TranslateContext(ctx, refs = refs)
    base = assemble(q′, ctx′)
    columns = nothing
    if !isempty(refs)
        columns = [SQLColumn(base.repl[ref]) for ref in refs]
    end
    c = complete_aligned(base, ctx′)
    with_args = SQLSyntax[]
    for cte_a in ctx.ctes
        !cte_a.external || continue
        cols = Symbol[name for name in keys(cte_a.a.cols)]
        if isempty(cols)
            push!(cols, :_)
        end
        tail = complete(cte_a.a)
        materialized = cte_a.materialized
        if materialized !== nothing
            tail = NOTE(materialized ? "MATERIALIZED" : "NOT MATERIALIZED", tail = tail)
        end
        arg = AS(name = cte_a.name, columns = cols, tail = tail)
        push!(with_args, arg)
    end
    if !isempty(with_args)
        c = WITH(tail = c, args = with_args, recursive = ctx.recursive[])
    end
    WITH_CONTEXT(tail = c, dialect = ctx.catalog.dialect, columns = columns)
end

function translate(q::SQLQuery, ctx)
    c = get(ctx.subs, q, nothing)
    if c === nothing
        c = convert(SQLSyntax, translate(q.head, TranslateContext(ctx, tail = q.tail)))
    end
    c
end

function translate(ctx::TranslateContext)
    translate(ctx.tail, ctx)
end

function translate(qs::Vector{SQLQuery}, ctx)
    SQLSyntax[translate(q, ctx) for q in qs]
end

translate(::Nothing, ctx) =
    nothing

function translate(q, ctx::TranslateContext, subs::Dict{SQLQuery, SQLSyntax})
    ctx′ = TranslateContext(ctx, subs = subs)
    translate(q, ctx′)
end

function translate(n::AggregateNode, ctx)
    args = translate(n.args, ctx)
    filter = translate(n.filter, ctx)
    AGG(n.name, args = args, filter = filter)
end

function translate(n::AsNode, ctx)
    translate(ctx)
end

function translate(n::BindNode, ctx)
    vars′ = ctx.vars
    for (name, i) in n.label_map
        depth = _cte_depth(ctx.vars, name) + 1
        vars′ = Base.ImmutableDict(vars′, (name, depth) => translate(n.args[i], ctx))
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    translate(ctx′)
end

function translate(n::BoundVariableNode, ctx)
    ctx.vars[(n.name, n.depth)]
end

function translate(n::FunctionNode, ctx)
    args = translate(n.args, ctx)
    if n.name === :and
        args′ = SQLSyntax[]
        for arg in args
            if @dissect(arg, LIT(val = true))
            elseif @dissect(arg, FUN(name = :and, args = (local args′′)))
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
        args′ = SQLSyntax[]
        for arg in args
            if @dissect(arg, LIT(val = false))
            elseif @dissect(arg, FUN(name = :or, args = (local args′′)))
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
        if length(args) == 1 && @dissect(args[1], LIT(val = (local val))) && val isa Bool
            return LIT(!val)
        end
    end
    FUN(name = n.name, args = args)
end

function translate(n::IsolatedNode, ctx)
    translate(ctx.defs[n.idx], ctx)
end

function translate(n::LinkedNode, ctx)
    base = assemble(n, ctx)
    complete_aligned(base, TranslateContext(ctx, refs = n.refs))
end

function translate(n::LiteralNode, ctx)
    LIT(n.val)
end

function translate(n::ResolvedNode, ctx)
    translate(ctx)
end

translate(n::SortNode, ctx) =
    SORT(value = n.value, nulls = n.nulls, tail = translate(ctx))

function translate(n::VariableNode, ctx)
    VAR(n.name)
end

function assemble(q::SQLQuery, ctx)
    assemble(q.head, TranslateContext(ctx, tail = q.tail))
end

assemble(ctx::TranslateContext) =
    assemble(ctx.tail, ctx)

function assemble(::Nothing, ctx)
    @assert isempty(ctx.refs)
    Assemblage(:_, nothing)
end

function assemble(n::AppendNode, ctx)
    base = assemble(ctx)
    branches = [ctx.tail => base]
    for arg in n.args
        push!(branches, arg => assemble(arg, ctx))
    end
    dups = Dict{SQLQuery, SQLQuery}()
    seen = Dict{Symbol, SQLQuery}()
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
    urefs = SQLQuery[]
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
    ss = SQLSyntax[]
    for (arg, a) in branches
        if a.name !== a_name
            a_name = :union
        end
        if @dissect(a.syntax, (local tail) |> SELECT(args = (local args))) && aligned_columns(urefs, repl, args) && !@dissect(tail, ORDER() || LIMIT())
            push!(ss, a.syntax)
            continue
        elseif !@dissect(a.syntax, SELECT() || UNION() || ORDER() || LIMIT())
            alias = nothing
            tail = a.syntax
        else
            alias = allocate_alias(ctx, a)
            tail = FROM(AS(name = alias, tail = complete(a)))
        end
        subs = make_subs(a, alias)
        cols = OrderedDict{Symbol, SQLSyntax}()
        for ref in urefs
            name = repl[ref]
            cols[name] = subs[ref]
        end
        s = SELECT(args = complete(cols), tail = tail)
        push!(ss, s)
    end
    s = UNION(all = true, args = ss[2:end], tail = ss[1])
    Assemblage(a_name, s, repl = repl, cols = dummy_cols)
end

function assemble(n::AsNode, ctx)
    refs′ = SQLQuery[]
    for ref in ctx.refs
        if @dissect(ref, (local tail) |> Nested())
            push!(refs′, tail)
        else
            push!(refs′, ref)
        end
    end
    base = assemble(TranslateContext(ctx, refs = refs′))
    repl′ = Dict{SQLQuery, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, (local tail) |> Nested())
            repl′[ref] = base.repl[tail]
        else
            repl′[ref] = base.repl[ref]
        end
    end
    Assemblage(n.name, base.syntax, cols = base.cols, repl = repl′)
end

function assemble(n::BindNode, ctx)
    vars′ = ctx.vars
    for (name, i) in n.label_map
        depth = _cte_depth(ctx.vars, name) + 1
        vars′ = Base.ImmutableDict(vars′, (name, depth) => translate(n.args[i], ctx))
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    assemble(ctx′)
end

function assemble(n::DefineNode, ctx)
    base = assemble(ctx)
    if !@dissect(base.syntax, SELECT() || UNION())
        base_alias = nothing
        s = base.syntax
    else
        base_alias = allocate_alias(ctx, base)
        s = FROM(AS(name = base_alias, tail = complete(base)))
    end
    subs = make_subs(base, base_alias)
    tr_cache = Dict{Symbol, SQLSyntax}()
    for (f, i) in n.label_map
        tr_cache[f] = translate(n.args[i], ctx, subs)
    end
    repl = Dict{SQLQuery, Symbol}()
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = (local name))) && name in keys(tr_cache)
            push!(trns, ref => tr_cache[name])
        else
            push!(trns, ref => subs[ref])
        end
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, s, cols = cols, repl = repl)
end

function assemble(n::FromFunctionNode, ctx)
    seen = Set{Symbol}()
    column_set = Set(n.columns)
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = (local name))) && name in column_set || error()
        if !(name in seen)
            push!(seen, name)
        end
    end
    tail = translate(ctx)
    lbl = label(ctx.tail)
    alias = allocate_alias(ctx, lbl)
    s = FROM(AS(name = alias, columns = n.columns, tail = tail))
    cols = OrderedDict{Symbol, SQLSyntax}()
    for col in n.columns
        col in seen || continue
        cols[col] = ID(name = col, tail = alias)
    end
    repl = Dict{SQLQuery, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = (local name)))
            repl[ref] = name
        end
    end
    Assemblage(lbl, s, cols = cols, repl = repl)
end

function assemble(n::FromIterateNode, ctx)
    cte_a = ctx.ctes[ctx.knot]
    name = cte_a.a.name
    alias = allocate_alias(ctx, name)
    tbl = convert(SQLSyntax, (cte_a.qualifiers, cte_a.name))
    s = FROM(AS(name = alias, tail = tbl))
    subs = make_subs(cte_a.a, alias)
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(name, s, cols = cols, repl = repl)
end

assemble(::FromNothingNode, ctx) =
    assemble(nothing, ctx)

function unwrap_repl(a::Assemblage)
    repl′ = Dict{SQLQuery, Symbol}()
    for (ref, name) in a.repl
        @dissect(ref, (local tail) |> Nested()) || error()
        repl′[tail] = name
    end
    Assemblage(a.name, a.syntax, cols = a.cols, repl = repl′)
end

function assemble(n::FromTableExpressionNode, ctx)
    cte_a = ctx.ctes[ctx.cte_map[(n.name, n.depth)]]
    alias = allocate_alias(ctx, n.name)
    tbl = convert(SQLSyntax, (cte_a.qualifiers, cte_a.name))
    s = FROM(AS(name = alias, tail = tbl))
    subs = make_subs(unwrap_repl(cte_a.a), alias)
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(n.name, s, cols = cols, repl = repl)
end

function assemble(n::FromTableNode, ctx)
    seen = Set{Symbol}()
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = (local name))) && name in keys(n.table.columns) || error()
        if !(name in seen)
            push!(seen, name)
        end
    end
    alias = allocate_alias(ctx, n.table.name)
    tbl = convert(SQLSyntax, (n.table.qualifiers, n.table.name))
    s = FROM(AS(name = alias, tail = tbl))
    cols = OrderedDict{Symbol, SQLSyntax}()
    for (name, col) in n.table.columns
        name in seen || continue
        cols[name] = ID(name = col.name, tail = alias)
    end
    repl = Dict{SQLQuery, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = (local name)))
            repl[ref] = name
        end
    end
    Assemblage(n.table.name, s, cols = cols, repl = repl)
end

function assemble(n::FromValuesNode, ctx)
    columns = Symbol[fieldnames(typeof(n.columns))...]
    column_set = Set{Symbol}(columns)
    seen = Set{Symbol}()
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = (local name))) && name in column_set || error()
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
    cols = OrderedDict{Symbol, SQLSyntax}()
    if isempty(rows)
        s = WHERE(false)
        for col in columns
            col in seen || continue
            cols[col] = LIT(missing)
        end
    elseif ctx.catalog.dialect.has_as_columns
        s = FROM(AS(alias, columns = column_aliases, tail = VALUES(rows)))
        for col in columns
            col in seen || continue
            cols[col] = ID(name = col, tail = alias)
        end
    else
        column_prefix = ctx.catalog.dialect.values_column_prefix
        column_index = ctx.catalog.dialect.values_column_index
        column_prefix !== nothing || error()
        s = FROM(AS(alias, tail = VALUES(rows)))
        for col in columns
            col in seen || continue
            name = Symbol(column_prefix, column_index)
            cols[col] = ID(name = name, tail = alias)
            column_index += 1
        end
    end
    repl = Dict{SQLQuery, Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = (local name)))
            repl[ref] = name
        end
    end
    Assemblage(:values, s, cols = cols, repl = repl)
end

function assemble(n::GroupNode, ctx)
    has_aggregates = any(ref -> @dissect(ref, Agg() || Agg() |> Nested()), ctx.refs)
    if isempty(n.by) && !has_aggregates # NOOP: already processed in link()
        return assemble(nothing, ctx)
    end
    base = assemble(ctx)
    if @dissect(base.syntax, local tail = nothing || FROM() || JOIN() || WHERE())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(name = base_alias, tail = complete(base)))
    end
    subs = make_subs(base, base_alias)
    by = SQLSyntax[subs[key] for key in n.by]
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = (local name)))
            @assert name in keys(n.label_map)
            push!(trns, ref => by[n.label_map[name]])
        elseif @dissect(ref, nothing |> Agg())
            push!(trns, ref => translate(ref, ctx, subs))
        elseif @dissect(ref, (local tail = nothing |> Agg()) |> Nested())
            push!(trns, ref => translate(tail, ctx, subs))
        end
    end
    if !has_aggregates && n.sets === nothing
        for name in keys(n.label_map)
            push!(trns, Get(name = name) => by[n.label_map[name]])
        end
    end
    repl, cols = make_repl_cols(trns)
    @assert !isempty(cols)
    if has_aggregates || n.sets !== nothing
        s = GROUP(by = by, sets = n.sets, tail = tail)
    else
        args = complete(cols)
        s = SELECT(distinct = true, args = args, tail = tail)
        cols = OrderedDict{Symbol, SQLSyntax}([name => ID(name) for name in keys(cols)])
    end
    return Assemblage(base.name, s, cols = cols, repl = repl)
end

function assemble(n::IterateNode, ctx)
    ctx′ = TranslateContext(ctx, vars = Base.ImmutableDict{Tuple{Symbol, Int}, SQLSyntax}())
    left = assemble(ctx)
    repl = Dict{SQLQuery, Symbol}()
    dups = Dict{SQLQuery, SQLQuery}()
    seen = Dict{Symbol, SQLQuery}()
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
    temp_union = Assemblage(label(n.iterator), left.syntax, cols = left.cols, repl = repl)
    union_alias = allocate_alias(ctx, temp_union)
    cte = CTEAssemblage(temp_union, name = union_alias)
    push!(ctx.ctes, cte)
    knot = lastindex(ctx.ctes)
    ctx = TranslateContext(ctx, knot = knot)
    right = assemble(n.iterator, ctx)
    urefs = SQLQuery[]
    for ref in ctx.refs
        !(ref in keys(dups)) || continue
        dups[ref] = ref
        push!(urefs, ref)
    end
    ss = SQLSyntax[]
    for (arg, a) in (ctx.tail => left, n.iterator => right)
        if @dissect(a.syntax, (local tail) |> SELECT(args = (local args))) && aligned_columns(urefs, repl, args) && !@dissect(tail, ORDER() || LIMIT())
            push!(ss, a.syntax)
            continue
        elseif !@dissect(a.syntax, SELECT() || UNION() || ORDER() || LIMIT())
            alias = nothing
            tail = a.syntax
        else
            alias = allocate_alias(ctx, a)
            tail = FROM(AS(name = alias, tail = complete(a)))
        end
        subs = make_subs(a, alias)
        cols = OrderedDict{Symbol, SQLSyntax}()
        for ref in urefs
            name = left.repl[ref]
            cols[name] = subs[ref]
        end
        s = SELECT(args = complete(cols), tail = tail)
        push!(ss, s)
    end
    union_syntax = UNION(all = true, args = ss[2:end], tail = ss[1])
    cols = OrderedDict{Symbol, SQLSyntax}()
    for ref in urefs
        name = left.repl[ref]
        cols[name] = ID(name)
    end
    union = Assemblage(right.name, union_syntax, cols = cols, repl = repl)
    ctx.ctes[knot] = CTEAssemblage(union, name = union_alias)
    ctx.recursive[] = true
    alias = allocate_alias(ctx, union)
    s = FROM(AS(name = alias, tail = ID(union_alias)))
    subs = make_subs(union, alias)
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(union.name, s, cols = cols, repl = repl)
end

function assemble(n::LimitNode, ctx)
    base = assemble(ctx)
    if @dissect(base.syntax, local tail = nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING() || ORDER())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(name = base_alias, tail = complete(base)))
    end
    s = LIMIT(offset = n.offset, limit = n.limit, tail = tail)
    subs = make_subs(base, base_alias)
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, s, cols = cols, repl = repl)
end

function assemble(n::LinkedNode, ctx)
    a = assemble(TranslateContext(ctx, refs = n.refs))
    n.n_ext_refs < length(n.refs) || return a
    dups = Set{Symbol}()
    for (k, ref) in enumerate(n.refs)
        col = a.repl[ref]
        if col in dups
            if k > n.n_ext_refs
                alias = allocate_alias(ctx, a)
                s = FROM(AS(name = alias, tail = complete(a)))
                subs = make_subs(a, alias)
                trns = Pair{SQLQuery, SQLSyntax}[]
                for ref in n.refs
                    push!(trns, ref => subs[ref])
                end
                repl, cols = make_repl_cols(trns)
                return Assemblage(a.name, s, cols = cols, repl = repl)
            end
        elseif !@dissect(a.cols[col], (nothing |> ID() || nothing |> ID() |> ID() || VAR() || LIT()))
            push!(dups, col)
        end
    end
    a
end

function assemble(n::OrderNode, ctx)
    base = assemble(ctx)
    @assert !isempty(n.by)
    if @dissect(base.syntax, local tail = nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(name = base_alias, tail = complete(base)))
    end
    subs = make_subs(base, base_alias)
    by = translate(n.by, ctx, subs)
    s = ORDER(by = by, tail = tail)
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, s, cols = cols, repl = repl)
end

function assemble(n::PaddingNode, ctx)
    base = assemble(ctx)
    if isempty(ctx.refs)
        return base
    end
    if !@dissect(base.syntax, SELECT() || UNION())
        base_alias = nothing
        s = base.syntax
    else
        base_alias = allocate_alias(ctx, base)
        s = FROM(AS(name = base_alias, tail = complete(base)))
    end
    subs = make_subs(base, base_alias)
    repl = Dict{SQLQuery, Symbol}()
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => translate(ref, ctx, subs))
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, s, cols = cols, repl = repl)
end

function assemble(n::PartitionNode, ctx)
    base = assemble(ctx)
    if @dissect(base.syntax, local tail = nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(name = base_alias, tail = complete(base)))
    end
    s = WINDOW(args = [], tail = tail)
    subs = make_subs(base, base_alias)
    ctx′ = TranslateContext(ctx, subs = subs)
    by = translate(n.by, ctx′)
    order_by = translate(n.order_by, ctx′)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLQuery, SQLSyntax}[]
    has_aggregates = false
    for ref in ctx.refs
        if @dissect(ref, nothing |> Agg()) && n.name === nothing
            @dissect(translate(ref, ctx′), AGG(name = (local name), args = (local args), filter = (local filter))) || error()
            push!(trns, ref => AGG(; name, args, filter, over = partition))
            has_aggregates = true
        elseif @dissect(ref, (local tail = nothing |> Agg()) |> Nested(name = (local name))) && name === n.name
            @dissect(translate(tail, ctx′), AGG(name = (local name), args = (local args), filter = (local filter))) || error()
            push!(trns, ref => AGG(; name, args, filter, over = partition))
            has_aggregates = true
        else
            push!(trns, ref => subs[ref])
        end
    end
    @assert has_aggregates
    repl, cols = make_repl_cols(trns)
    Assemblage(base.name, s, cols = cols, repl = repl)
end

_outer_safe(a::Assemblage) =
    all(@dissect(col, (nothing |> ID() |> ID())) for col in values(a.cols))

function assemble(n::RoutedJoinNode, ctx)
    left = assemble(ctx)
    if @dissect(left.syntax, local tail = FROM() || JOIN()) && (!n.right || _outer_safe(left))
        left_alias = nothing
    else
        left_alias = allocate_alias(ctx, left)
        tail = FROM(AS(name = left_alias, tail = complete(left)))
    end
    lateral = n.lateral
    subs = make_subs(left, left_alias)
    if lateral
        right = assemble(n.joinee, TranslateContext(ctx, subs = subs))
    else
        right = assemble(n.joinee, ctx)
    end
    if @dissect(right.syntax, (local joinee = (ID() || AS())) |> FROM()) && (!n.left || _outer_safe(right))
        for (ref, name) in right.repl
            subs[ref] = right.cols[name]
        end
        if ctx.catalog.dialect.has_implicit_lateral
            lateral = false
        end
    else
        right_alias = allocate_alias(ctx, right)
        joinee = AS(name = right_alias, tail = complete(right))
        right_cache = Dict{Symbol, SQLSyntax}()
        for (ref, name) in right.repl
            subs[ref] = get(right_cache, name) do
                ID(name = name, tail = right_alias)
            end
        end
    end
    on = translate(n.on, ctx, subs)
    s = JOIN(joinee = joinee, on = on, left = n.left, right = n.right, lateral = lateral, tail = tail)
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(left.name, s, cols = cols, repl = repl)
end

function assemble(n::SelectNode, ctx)
    base = assemble(ctx)
    if !@dissect(base.syntax, SELECT() || UNION())
        base_alias = nothing
        tail = base.syntax
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(name = base_alias, tail = complete(base)))
    end
    subs = make_subs(base, base_alias)
    cols = OrderedDict{Symbol, SQLSyntax}()
    for (name, i) in n.label_map
        col = n.args[i]
        cols[name] = translate(col, ctx, subs)
    end
    s = SELECT(args = complete(cols), tail = tail)
    cols = OrderedDict{Symbol, SQLSyntax}([name => ID(name) for name in keys(cols)])
    repl = Dict{SQLQuery, Symbol}()
    for ref in ctx.refs
        @dissect(ref, nothing |> Get(name = (local name))) || error()
        repl[ref] = name
    end
    Assemblage(base.name, s, cols = cols, repl = repl)
end

function merge_conditions(s1, s2)
    if @dissect(s1, FUN(name = :and, args = (local args1)))
        if @dissect(s2, FUN(name = :and, args = (local args2)))
            return FUN(:and, args1..., args2...)
        else
            return FUN(:and, args1..., s2)
        end
    elseif @dissect(s2, FUN(name = :and, args = (local args2)))
        return FUN(:and, s1, args2...)
    else
        return FUN(:and, s1, s2)
    end
end

function assemble(n::WhereNode, ctx)
    base = assemble(ctx)
    if @dissect(base.syntax, nothing || FROM() || JOIN() || WHERE() || HAVING()) ||
       @dissect(base.syntax, GROUP(by = (local by))) && !isempty(by)
        subs = make_subs(base, nothing)
        condition = translate(n.condition, ctx, subs)
        if @dissect(condition, LIT(val = true))
            return base
        end
        if @dissect(base.syntax, (local tail) |> WHERE(condition = (local tail_condition)))
            condition = merge_conditions(tail_condition, condition)
            s = WHERE(tail = tail, condition = condition)
        elseif @dissect(base.syntax, GROUP())
            s = HAVING(tail = base.syntax, condition = condition)
        elseif @dissect(base.syntax, (local tail) |> HAVING(condition = (local tail_condition)))
            condition = merge_conditions(tail_condition, condition)
            s = HAVING(condition = condition, tail = tail)
        else
            s = WHERE(condition = condition, tail = base.syntax)
        end
    else
        base_alias = allocate_alias(ctx, base)
        tail = FROM(AS(name = base_alias, tail = complete(base)))
        subs = make_subs(base, base_alias)
        condition = translate(n.condition, ctx, subs)
        if @dissect(condition, LIT(val = true))
            return base
        end
        s = WHERE(condition = condition, tail = tail)
    end
    trns = Pair{SQLQuery, SQLSyntax}[]
    for ref in ctx.refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(base.name, s, cols = cols, repl = repl)
end

function assemble(n::WithNode, ctx)
    cte_map′ = ctx.cte_map
    # FIXME: variable pushed into a CTE
    ctx′ = TranslateContext(ctx, vars = Base.ImmutableDict{Tuple{Symbol, Int}, SQLSyntax}())
    for (name, i) in n.label_map
        a = assemble(n.args[i], ctx)
        alias = allocate_alias(ctx, a)
        cte = CTEAssemblage(a, name = alias, materialized = n.materialized)
        push!(ctx.ctes, cte)
        depth = _cte_depth(ctx.cte_map, name) + 1
        cte_map′ = Base.ImmutableDict(cte_map′, (name, depth) => lastindex(ctx.ctes))
    end
    assemble(TranslateContext(ctx, cte_map = cte_map′))
end

function assemble(n::WithExternalNode, ctx)
    cte_map′ = ctx.cte_map
    ctx′ = TranslateContext(ctx, vars = Base.ImmutableDict{Tuple{Symbol, Int}, SQLSyntax}())
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
        depth = _cte_depth(ctx.cte_map, name) + 1
        cte_map′ = Base.ImmutableDict(cte_map′, (name, depth) => lastindex(ctx.ctes))
    end
    assemble(TranslateContext(ctx, cte_map = cte_map′))
end
