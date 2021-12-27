# Translating a SQL node graph to a SQL statement.

function render(n; dialect = :default)
    actx = AnnotateContext()
    n′ = annotate(convert(SQLNode, n), actx)
    @debug "FunSQL.annotate\n" * sprint(pprint, n′) _group = Symbol("FunSQL.annotate")
    resolve!(actx)
    @debug "FunSQL.resolve!\n" * sprint(pprint, n′) _group = Symbol("FunSQL.resolve!")
    link!(actx)
    @debug "FunSQL.link!\n" * sprint(pprint, n′) _group = Symbol("FunSQL.link!")
    tctx = TranslateContext(dialect, actx.path_map)
    c = translate_toplevel(n′, tctx)
    @debug "FunSQL.translate\n" * sprint(pprint, c) _group = Symbol("FunSQL.translate")
    sql = render(c, dialect = dialect)
    @debug "FunSQL.render\n" * sql _group = Symbol("FunSQL.render")
    sql
end


# Partially constructed query.

struct Assemblage
    clause::Union{SQLClause, Nothing}       # A SQL subquery (possibly without SELECT clause).
    cols::OrderedDict{Symbol, SQLClause}    # SELECT arguments, if necessary.
    repl::Dict{SQLNode, Symbol}             # Maps a reference node to a column alias.

    Assemblage(clause; cols = OrderedDict{Symbol, SQLClause}(), repl = Dict{SQLNode, Symbol}()) =
        new(clause, cols, repl)
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
        push!(args, LIT(missing))
    end
    args
end

# Add a SELECT clause to a partially assembled subquery (if necessary).
function complete(a::Assemblage)
    clause = a.clause
    if !@dissect(clause, SELECT() || UNION())
        args = complete(a.cols)
        clause = SELECT(over = clause, args = args)
    else
        @assert isempty(a.cols)
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

# Build a node->alias map for a UNION query.
function make_repl_only(refs::Vector{SQLNode})::Dict{SQLNode, Symbol}
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
        repl[ref] = name′
        dups[name′] = 1
    end
    repl
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


# Translating context.

struct TranslateContext
    dialect::SQLDialect
    path_map::PathMap
    aliases::Dict{Symbol, Int}
    with_map::OrderedDict{SQLNode, Pair{Symbol, Assemblage}}
    recursive::Ref{Bool}
    vars::Dict{Symbol, SQLClause}
    subs::Dict{SQLNode, SQLClause}

    TranslateContext(dialect, path_map::PathMap) =
        new(dialect,
            path_map,
            Dict{Symbol, Int}(),
            OrderedDict{SQLNode, Pair{Symbol, Assemblage}}(),
            Ref(false),
            Dict{Symbol, SQLClause}(),
            Dict{SQLNode, SQLClause}())

    function TranslateContext(ctx::TranslateContext; vars = nothing, subs = nothing)
        new(ctx.dialect,
            ctx.path_map,
            ctx.aliases,
            ctx.with_map,
            ctx.recursive,
            something(vars, ctx.vars),
            something(subs, ctx.subs))
    end
end

allocate_alias(ctx::TranslateContext, n::SQLNode) =
    allocate_alias(ctx, (n[]::BoxNode).type.name)

function allocate_alias(ctx::TranslateContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

function translate_toplevel(n::SQLNode, ctx)
    c = translate(n, ctx)
    if !isempty(ctx.with_map)
        args = SQLClause[]
        for (alias, a) in values(ctx.with_map)
            push!(args, CTE(over = complete(a), name = alias))
        end
        c = WITH(over = c, args = args, recursive = ctx.recursive[])
    end
    c
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

function translate(n::IntBindNode, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.args[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    translate(n.over, ctx′)
end

function translate(n::BoxNode, ctx)
    base = assemble(n, ctx)
    complete(base)
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
            elseif length(args) == 2 && @dissect(args[1], LIT(val = val)) && val == $default
                args[2]
            elseif @dissect(args[1], OP(name = name, args = args′)) && name === $(QuoteNode(op))
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
                if length(args) == 2 && @dissect(args[2], SELECT() || UNION())
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
    OP("IS NOT", SQLClause[translate(arg, ctx) for arg in n.args]..., missing)

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

assemble(n::SQLNode, ctx) =
    assemble(n[], ctx)

function assemble(n::BoxNode, ctx)
    refs′ = SQLNode[]
    for ref in n.refs
        if @dissect(ref, over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    base = assemble(n.over, refs′, ctx)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if @dissect(ref, over |> HandleBoundNode(handle = handle)) && handle == n.handle
            repl′[ref] = base.repl[over]
        else
            repl′[ref] = base.repl[ref]
        end
    end
    Assemblage(base.clause, cols = base.cols, repl = repl′)
end

assemble(n::SQLNode, refs, ctx) =
    assemble(n[], refs, ctx)

function assemble(::Nothing, refs, ctx)
    @assert isempty(refs)
    Assemblage(nothing)
end

function assemble(n::AppendNode, refs, ctx)
    base = assemble(n.over, ctx)
    branches = [n.over => base]
    for arg in n.args
        push!(branches, arg => assemble(arg, ctx))
    end
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in refs
        name = base.repl[ref]
        if name in keys(seen)
            other_ref = seen[name]
            if all(a.repl[ref] === a.repl[other_ref] for (arg, a) in branches)
                dups[ref] = seen[name]
            end
        else
            seen[name] = ref
        end
    end
    urefs = SQLNode[ref for ref in refs if !(ref in keys(dups))]
    repl = make_repl_only(urefs)
    for (ref, uref) in dups
        repl[ref] = repl[uref]
    end
    cs = SQLClause[]
    for (arg, a) in branches
        if !@dissect(a.clause, SELECT() || UNION())
            alias = nothing
            tail = a.clause
        else
            alias = allocate_alias(ctx, arg)
            tail = FROM(AS(over = complete(a), name = alias))
        end
        subs = make_subs(a, alias)
        cols = OrderedDict{Symbol, SQLClause}()
        for ref in refs
            !(ref in keys(dups)) || continue
            name = repl[ref]
            cols[name] = subs[ref]
        end
        c = SELECT(over = tail, args = complete(cols))
        push!(cs, c)
    end
    c = UNION(over = cs[1], all = true, args = cs[2:end])
    Assemblage(c, repl = repl)
end

function assemble(n::AsNode, refs, ctx)
    base = assemble(n.over, ctx)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect(ref, over |> NameBound())
            repl′[ref] = base.repl[over]
        else
            repl′[ref] = base.repl[ref]
        end
    end
    Assemblage(base.clause, cols = base.cols, repl = repl′)
end

function assemble(n::DefineNode, refs, ctx)
    base = assemble(n.over, ctx)
    if !any(ref -> @dissect(ref, Get(name = name)) && name in keys(n.label_map), refs)
        return base
    end
    if !@dissect(base.clause, SELECT() || UNION())
        base_alias = nothing
        c = base.clause
    else
        base_alias = allocate_alias(ctx, n.over)
        c = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    tr_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if @dissect(ref, nothing |> Get(name = name)) && name in keys(n.label_map)
            col = get!(tr_cache, name) do
                def = n.args[n.label_map[name]]
                translate(def, ctx, subs)
            end
            push!(trns, ref => col)
        else
            push!(trns, ref => subs[ref])
        end
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(c, cols = cols, repl = repl)
end

assemble(::FromNothingNode, refs, ctx) =
    assemble(nothing, refs, ctx)

function unwrap_repl(a::Assemblage)
    repl′ = Dict{SQLNode, Symbol}()
    for (ref, name) in a.repl
        @dissect(ref, over |> NameBound()) || error()
        repl′[over] = name
    end
    Assemblage(a.clause, cols = a.cols, repl = repl′)
end

function assemble(n::FromReferenceNode, refs, ctx)
    (alias, a) = ctx.with_map[n.over]
    a = unwrap_repl(a)
    c = FROM(over = ID(alias))
    subs = make_subs(a, alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::FromTableNode, refs, ctx)
    seen = Set{Symbol}()
    for ref in refs
        @dissect(ref, nothing |> Get(name = name)) && name in n.table.column_set || error()
        if !(name in seen)
            push!(seen, name)
        end
    end
    alias = allocate_alias(ctx, n.table.name)
    tbl = ID(over = n.table.schema, name = n.table.name)
    c = FROM(AS(over = tbl, name = alias))
    cols = OrderedDict{Symbol, SQLClause}()
    for col in n.table.columns
        col in seen || continue
        cols[col] = ID(over = alias, name = col)
    end
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect(ref, nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::GroupNode, refs, ctx)
    has_aggregates = any(ref -> @dissect(ref, Agg()), refs)
    if isempty(n.by) && !has_aggregates
        return assemble(nothing, refs, ctx)
    end
    base = assemble(n.over, ctx)
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    by = translate(n.by, ctx, subs)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if @dissect(ref, nothing |> Get(name = name))
            @assert name in keys(n.label_map)
            push!(trns, ref => by[n.label_map[name]])
        elseif @dissect(ref, nothing |> Agg(name = name))
            push!(trns, ref => translate(ref, ctx, subs))
        end
    end
    repl, cols = make_repl_cols(trns)
    @assert !isempty(cols)
    if has_aggregates
        c = GROUP(over = tail, by = by)
        return Assemblage(c, cols = cols, repl = repl)
    else
        args = complete(cols)
        c = SELECT(over = tail, distinct = true, args = args)
        return Assemblage(c, repl = repl)
    end
end

assemble(n::HighlightNode, refs, ctx) =
    assemble(n.over, ctx)

function assemble(n::IntBindNode, refs, ctx)
    vars′ = copy(ctx.vars)
    for (name, i) in n.label_map
        vars′[name] = translate(n.args[i], ctx)
    end
    ctx′ = TranslateContext(ctx, vars = vars′)
    assemble(n.over, ctx′)
end

function assemble(n::IntIterateNode, refs, ctx)
    ctx′ = TranslateContext(ctx, vars = Dict{Symbol, SQLClause}())
    base = unwrap_repl(assemble(n.over, ctx′))
    @assert @dissect(base.clause, FROM())
    subs = make_subs(base, nothing)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(base.clause, cols = cols, repl = repl)
end

function assemble(n::IntJoinNode, refs, ctx)
    left = assemble(n.over, ctx)
    if @dissect(left.clause, tail := FROM() || JOIN())
        left_alias = nothing
    else
        left_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(left), name = left_alias))
    end
    lateral = !isempty(n.lateral)
    subs = make_subs(left, left_alias)
    if lateral
        right = assemble(n.joinee, TranslateContext(ctx, subs = subs))
    else
        right = assemble(n.joinee, ctx)
    end
    if @dissect(right.clause, (joinee := nothing |> ID() |> AS(name = right_alias)) |> FROM()) ||
       @dissect(right.clause, (joinee := nothing |> ID(name = right_alias)) |> FROM())
        for (ref, name) in right.repl
            subs[ref] = right.cols[name]
        end
    else
        right_alias = allocate_alias(ctx, n.joinee)
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
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::KnotNode, refs, ctx)
    left = assemble(n.over, ctx)
    repl = Dict{SQLNode, Symbol}()
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in refs
        if @dissect(ref, over |> NameBound())
            name = left.repl[over]
            repl[ref] = name
            if name in keys(seen)
                dups[over] = seen[name]
            else
                seen[name] = over
            end
        else
            error()
        end
    end
    temp_union = Assemblage(left.clause, cols = left.cols, repl = repl)
    union_alias = allocate_alias(ctx, n.name)
    ctx.with_map[SQLNode(n.box)] = union_alias => temp_union
    right = unwrap_repl(assemble(n.iterator, ctx))
    cs = SQLClause[]
    for (arg, a) in (n.over => left, n.iterator => right)
        if !@dissect(a.clause, SELECT() || UNION())
            alias = nothing
            tail = a.clause
        else
            alias = allocate_alias(ctx, arg)
            tail = FROM(AS(over = complete(a), name = alias))
        end
        subs = make_subs(a, alias)
        cols = OrderedDict{Symbol, SQLClause}()
        for ref in refs
            @dissect(ref, over |> NameBound())
            if over in keys(dups)
                @assert a.repl[over] === a.repl[dups[over]] "FIXME!"
                continue
            end
            name = left.repl[over]
            cols[name] = subs[over]
        end
        c = SELECT(over = tail, args = complete(cols))
        push!(cs, c)
    end
    union_clause = UNION(over = cs[1], all = true, args = cs[2:end])
    union = Assemblage(union_clause, repl = repl)
    ctx.with_map[SQLNode(n.box)] = union_alias => union
    ctx.recursive[] = true
    c = FROM(over = ID(union_alias))
    subs = make_subs(union, union_alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::LimitNode, refs, ctx)
    base = assemble(n.over, ctx)
    if n.offset === nothing && n.limit === nothing
        return base
    end
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING() || ORDER())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    c = LIMIT(over = tail, offset = n.offset, limit = n.limit)
    subs = make_subs(base, base_alias)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::OrderNode, refs, ctx)
    base = assemble(n.over, ctx)
    if isempty(n.by)
        return base
    end
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    by = translate(n.by, ctx, subs)
    c = ORDER(over = tail, by = by)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::PartitionNode, refs, ctx)
    base = assemble(n.over, ctx)
    if !any(ref -> @dissect(ref, Agg()), refs)
        return base
    end
    if @dissect(base.clause, tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        base_alias = nothing
    else
        base_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    c = WINDOW(over = tail, args = [])
    subs = make_subs(base, base_alias)
    ctx′ = TranslateContext(ctx, subs = subs)
    by = translate(n.by, ctx′)
    order_by = translate(n.order_by, ctx′)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if @dissect(ref, nothing |> Agg(name = name))
            push!(trns, ref => partition |> translate(ref, ctx′))
        else
            push!(trns, ref => subs[ref])
        end
    end
    repl, cols = make_repl_cols(trns)
    Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::SelectNode, refs, ctx)
    base = assemble(n.over, ctx)
    if !@dissect(base.clause, SELECT() || UNION())
        base_alias = nothing
        tail = base.clause
    else
        base_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_alias))
    end
    subs = make_subs(base, base_alias)
    cols = OrderedDict{Symbol, SQLClause}()
    for (name, i) in n.label_map
        col = n.args[i]
        cols[name] = translate(col, ctx, subs)
    end
    c = SELECT(over = tail, args = complete(cols))
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        @dissect(ref, nothing |> Get(name = name)) || error()
        repl[ref] = name
    end
    Assemblage(c, repl = repl)
end

function merge_conditions(c1, c2)
    if @dissect(c1, OP(name = :AND, args = args1))
        if @dissect(c2, OP(name = :AND, args = args2))
            return OP(:AND, args1..., args2...)
        else
            return OP(:AND, args1..., c2)
        end
    elseif @dissect(c2, OP(name = :AND, args = args2))
        return OP(:AND, c1, args2...)
    else
        return OP(:AND, c1, c2)
    end
end

function assemble(n::WhereNode, refs, ctx)
    base = assemble(n.over, ctx)
    if @dissect(base.clause, nothing || FROM() || JOIN() || WHERE() || HAVING()) ||
       @dissect(base.clause, GROUP(by = by)) && !isempty(by)
        subs = make_subs(base, nothing)
        condition = translate(n.condition, ctx, subs)
        if @dissect(condition, LIT(val = val)) && val === true
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
        base_alias = allocate_alias(ctx, n.over)
        tail = FROM(AS(over = complete(base), name = base_alias))
        subs = make_subs(base, base_alias)
        condition = translate(n.condition, ctx, subs)
        if @dissect(condition, LIT(val = val)) && val === true
            return base
        end
        c = WHERE(over = tail, condition = condition)
    end
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        push!(trns, ref => subs[ref])
    end
    repl, cols = make_repl_cols(trns)
    return Assemblage(c, cols = cols, repl = repl)
end

function assemble(n::WithNode, refs, ctx)
    ctx′ = TranslateContext(ctx, vars = Dict{Symbol, SQLClause}())
    for arg in n.args
        a = assemble(arg, ctx)
        alias = allocate_alias(ctx, arg)
        ctx.with_map[arg] = alias => a
    end
    assemble(n.over, ctx)
end

