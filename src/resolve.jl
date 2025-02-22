# Resolving node types.

struct ResolveContext
    catalog::SQLCatalog
    tail::Union{SQLQuery, Nothing}
    path::Vector{SQLQuery}
    path_subs::Dict{SQLQuery, SQLQuery}
    row_type::RowType
    cte_types::Base.ImmutableDict{Symbol, Tuple{Int, RowType}}
    var_types::Base.ImmutableDict{Symbol, Tuple{Int, ScalarType}}
    knot_type::Union{RowType, Nothing}
    implicit_knot::Bool

    ResolveContext(catalog) =
        new(catalog,
            nothing,
            SQLQuery[],
            Dict{SQLQuery, SQLQuery}(),
            EMPTY_ROW,
            Base.ImmutableDict{Symbol, Tuple{Int, RowType}}(),
            Base.ImmutableDict{Symbol, Tuple{Int, ScalarType}}(),
            nothing,
            false)

    ResolveContext(
            ctx::ResolveContext;
            tail = ctx.tail,
            row_type = ctx.row_type,
            cte_types = ctx.cte_types,
            var_types = ctx.var_types,
            knot_type = ctx.knot_type,
            implicit_knot = ctx.implicit_knot) =
        new(ctx.catalog,
            tail,
            ctx.path,
            ctx.path_subs,
            row_type,
            cte_types,
            var_types,
            knot_type,
            implicit_knot)
end

get_path(ctx::ResolveContext) =
    SQLQuery[get(ctx.path_subs, q, q) for q in ctx.path]

function row_type(q::SQLQuery)
    @dissect(q, Resolved(type = (local type)::RowType)) || throw(IllFormedError())
    type
end

function scalar_type(q::SQLQuery)
    @dissect(q, Resolved(type = (local type)::ScalarType)) || throw(IllFormedError())
    type
end

function type(q::SQLQuery)
    @dissect(q, Resolved(type = (local t))) || throw(IllFormedError())
    t
end

function resolve(q::SQLQuery)
    @dissect(q, (local q′) |> WithContext(catalog = (local catalog))) || throw(IllFormedError())
    ctx = ResolveContext(catalog)
    WithContext(tail = resolve(q′, ctx), catalog = catalog)
end

function resolve(ctx::ResolveContext)
    resolve(ctx.tail, ctx)
end

function resolve(q::SQLQuery, ctx)
    !@dissect(q, Resolved()) || return q
    push!(ctx.path, q)
    try
        convert(SQLQuery, resolve(q.head, ResolveContext(ctx, tail = q.tail)))
    finally
        pop!(ctx.path)
    end
end

resolve(qs::Vector{SQLQuery}, ctx) =
    SQLQuery[resolve(q, ctx) for q in qs]

function resolve(::Nothing, ctx)
    t = ctx.knot_type
    if t !== nothing && ctx.implicit_knot
        q = FromIterate()
    else
        q = FromNothing()
        t = EMPTY_ROW
    end
    Resolved(t, tail = q)
end

resolve(q, ctx, t) =
    resolve(q, ResolveContext(ctx, row_type = t))

resolve(n::AbstractSQLNode, ctx) =
    throw(IllFormedError(path = get_path(ctx)))

function resolve_scalar(ctx::ResolveContext)
    resolve_scalar(ctx.tail, ctx)
end

function resolve_scalar(q::SQLQuery, ctx)
    push!(ctx.path, q)
    try
        convert(SQLQuery, resolve_scalar(q.head, ResolveContext(ctx, tail = q.tail)))
    finally
        pop!(ctx.path)
    end
end

function resolve_scalar(qs::Vector{SQLQuery}, ctx)
    SQLQuery[resolve_scalar(q, ctx) for q in qs]
end

resolve_scalar(q, ctx, t) =
    resolve_scalar(q, ResolveContext(ctx, row_type = t))

function resolve_scalar(n::TabularNode, ctx)
    q′ = resolve(n, ResolveContext(ctx, implicit_knot = false))
    Resolved(ScalarType(), tail = q′)
end

function unnest(q, base, ctx)
    while @dissect(q, (local tail) |> Get(name = (local name)))
        base = Nested(tail = base, name = name)
        q = tail
    end
    if q !== nothing
        throw(IllFormedError(path = get_path(ctx)))
    end
    base
end

function resolve_scalar(n::AggregateNode, ctx)
    if ctx.tail !== nothing
        q′ = unnest(ctx.tail, Agg(name = n.name, args = n.args, filter = n.filter), ctx)
        return resolve_scalar(q′, ctx)
    end
    t = ctx.row_type.group
    if !(t isa RowType)
        error_type = REFERENCE_ERROR_TYPE.UNEXPECTED_AGGREGATE
        throw(ReferenceError(error_type, path = get_path(ctx)))
    end
    ctx′ = ResolveContext(ctx, row_type = t)
    args′ = resolve_scalar(n.args, ctx′)
    filter′ = nothing
    if n.filter !== nothing
        filter′ = resolve_scalar(n.filter, ctx′)
    end
    q′ = Agg(name = n.name, args = args′, filter = filter′)
    Resolved(ScalarType(), tail = q′)
end

function resolve(n::AppendNode, ctx)
    tail = ctx.tail
    args = n.args
    if tail === nothing && !ctx.implicit_knot
        if !isempty(args)
            tail = args[1]
            args = args[2:end]
        else
            tail = Where(false)
        end
    end
    tail′ = resolve(tail, ctx)
    args′ = resolve(args, ResolveContext(ctx, implicit_knot = false))
    q′ = Append(args = args′, tail = tail′)
    t = row_type(tail′)
    for arg in args′
        t = intersect(t, row_type(arg))
    end
    Resolved(t, tail = q′)
end

function resolve(n::AsNode, ctx)
    tail′ = resolve(ctx)
    q′ = As(name = n.name, tail = tail′)
    Resolved(type(tail′), tail = q′)
end

function resolve_scalar(n::AsNode, ctx)
    tail′ = resolve_scalar(ctx)
    q′ = As(name = n.name, tail = tail′)
    Resolved(type(tail′), tail = q′)
end

function resolve(n::BindNode, ctx, scalar = false)
    args′ = resolve_scalar(n.args, ctx)
    var_types′ = ctx.var_types
    for (name, i) in n.label_map
        v = get(ctx.var_types, name, nothing)
        depth = 1 + (v !== nothing ? v[1] : 0)
        t = scalar_type(args′[i])
        var_types′ = Base.ImmutableDict(var_types′, name => (depth, t))
    end
    ctx′ = ResolveContext(ctx, var_types = var_types′)
    tail′ = !scalar ? resolve(ctx′) : resolve_scalar(ctx′)
    q′ = Bind(args = args′, label_map = n.label_map, tail = tail′)
    Resolved(type(tail′), tail = q′)
end

resolve_scalar(n::BindNode, ctx) =
    resolve(n, ctx, true)

function resolve_scalar(n::NestedNode, ctx)
    t = get(ctx.row_type.fields, n.name, EmptyType())
    if !(t isa RowType)
        error_type =
            t isa EmptyType ?
                REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE
        throw(ReferenceError(error_type, name = n.name, path = get_path(ctx)))
    end
    tail′ = resolve_scalar(ctx.tail, ctx, t)
    q′ = Nested(name = n.name, tail = tail′)
    Resolved(type(tail′), tail = q′)
end

function resolve(n::DefineNode, ctx)
    tail′ = resolve(ctx)
    t = row_type(tail′)
    anchor =
        n.before isa Symbol ? n.before :
        n.before && !isempty(t.fields) ? first(first(t.fields)) :
        n.after isa Symbol ? n.after :
        n.after && !isempty(t.fields) ? first(last(t.fields)) :
        nothing
    if anchor !== nothing && !haskey(t.fields, anchor)
        throw(ReferenceError(REFERENCE_ERROR_TYPE.UNDEFINED_NAME, name = anchor, path = get_path(ctx)))
    end
    before = n.before isa Symbol || n.before
    after = n.after isa Symbol || n.after
    args′ = resolve_scalar(n.args, ctx, t)
    fields = FieldTypeMap()
    for (f, ft) in t.fields
        i = get(n.label_map, f, nothing)
        if f === anchor
            if after && i === nothing
                fields[f] = ft
            end
            for (l, j) in n.label_map
                fields[l] = type(args′[j])
            end
            if before && i === nothing
                fields[f] = ft
            end
        elseif i !== nothing
            if anchor === nothing
                fields[f] = type(args′[i])
            end
        else
            fields[f] = ft
        end
    end
    if anchor === nothing
        for (l, j) in n.label_map
            if !haskey(fields, l)
                fields[l] = type(args′[j])
            end
        end
    end
    q′ = Define(args = args′, label_map = n.label_map, tail = tail′)
    Resolved(RowType(fields, t.group), tail = q′)
end

function RowType(table::SQLTable)
    fields = FieldTypeMap()
    for f in keys(table.columns)
        fields[f] = ScalarType()
    end
    RowType(fields)
end

function resolve(n::FromNode, ctx)
    source = n.source
    if source isa SQLTable
        q′ = FromTable(table = source)
        t = RowType(source)
    elseif source isa Symbol
        v = get(ctx.cte_types, source, nothing)
        if v !== nothing
            (depth, t) = v
            q′ = FromTableExpression(source, depth)
        else
            table = get(ctx.catalog, source, nothing)
            if table === nothing
                throw(
                    ReferenceError(
                        REFERENCE_ERROR_TYPE.UNDEFINED_TABLE_REFERENCE,
                        name = source,
                        path = get_path(ctx)))
            end
            q′ = FromTable(table = table)
            t = RowType(table)
        end
    elseif source isa IterateSource
        t = ctx.knot_type
        if t === nothing
            throw(
                ReferenceError(
                    REFERENCE_ERROR_TYPE.INVALID_SELF_REFERENCE,
                    path = get_path(ctx)))
        end
        q′ = FromIterate()
    elseif source isa ValuesSource
        q′ = FromValues(columns = source.columns)
        fields = FieldTypeMap()
        for f in keys(source.columns)
            fields[f] = ScalarType()
        end
        t = RowType(fields)
    elseif source isa FunctionSource
        q′ = FromFunction(columns = source.columns, tail = resolve_scalar(source.query, ctx))
        fields = FieldTypeMap()
        for f in source.columns
            fields[f] = ScalarType()
        end
        t = RowType(fields)
    elseif source === nothing
        q′ = FromNothing()
        t = RowType()
    else
        error()
    end
    Resolved(t, tail = q′)
end

function resolve_scalar(n::FunctionNode, ctx)
    args′ = resolve_scalar(n.args, ctx)
    q′ = Fun(name = n.name, args = args′)
    Resolved(ScalarType(), tail = q′)
end

function rebase(q::SQLQuery, ctx::ResolveContext)
    ctx.tail !== nothing || return q
    q′ =
        if q.tail !== nothing
            SQLQuery(rebase(q.tail, ctx), q.head)
        else
            SQLQuery(ctx.tail, q.head)
        end
    ctx.path_subs[q′] = q
    q′
end

resolve(n::FunSQLMacroNode, ctx) =
    resolve(ResolveContext(ctx, tail = rebase(n.query, ctx)))

resolve_scalar(n::FunSQLMacroNode, ctx) =
    resolve_scalar(ResolveContext(ctx, tail = rebase(n.query, ctx)))

function resolve(n::GetNode, ctx)
    if ctx.tail !== nothing
        q′ = unnest(ctx.tail, Get(n.name), ctx)
        return resolve(q′, ctx)
    end
    resolve(FromNode(n.name), ctx)
end

function resolve_scalar(n::GetNode, ctx)
    if ctx.tail !== nothing
        q′ = unnest(ctx.tail, Get(n.name), ctx)
        return resolve_scalar(q′, ctx)
    end
    t = get(ctx.row_type.fields, n.name, EmptyType())
    if !(t isa ScalarType)
        error_type =
            t isa EmptyType ?
                REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE
        throw(ReferenceError(error_type, name = n.name, path = get_path(ctx)))
    end
    Resolved(t, tail = convert(SQLQuery, n))
end

function resolve(n::GroupNode, ctx)
    tail′ = resolve(ctx)
    t = row_type(tail′)
    by′ = resolve_scalar(n.by, ctx, t)
    fields = FieldTypeMap()
    for (name, i) in n.label_map
        fields[name] = type(by′[i])
    end
    group = t
    if n.name !== nothing
        fields[n.name] = RowType(FieldTypeMap(), group)
        group = EmptyType()
    end
    q′ = Group(by = by′, sets = n.sets, label_map = n.label_map, tail = tail′)
    Resolved(RowType(fields, group), tail = q′)
end

resolve(::HighlightNode, ctx) =
    resolve(ctx)

resolve_scalar(::HighlightNode, ctx) =
    resolve_scalar(ctx)

function resolve(n::IntoNode, ctx)
    tail′ = resolve(ctx)
    t = row_type(tail′)
    q′ = Into(name = n.name, tail = tail′)
    Resolved(RowType(FieldTypeMap(n.name => t)), tail = q′)
end

function resolve(n::IterateNode, ctx)
    tail′ = resolve(ResolveContext(ctx, knot_type = nothing, implicit_knot = false))
    t = row_type(tail′)
    iterator′ = resolve(n.iterator, ResolveContext(ctx, knot_type = t, implicit_knot = true))
    iterator_t = row_type(iterator′)
    while !issubset(t, iterator_t)
        t = intersect(t, iterator_t)
        iterator′ = resolve(n.iterator, ResolveContext(ctx, knot_type = t, implicit_knot = true))
        iterator_t = row_type(iterator′)
    end
    q′ = Iterate(iterator = iterator′, tail = tail′)
    Resolved(t, tail = q′)
end

function resolve(n::JoinNode, ctx)
    if n.swap
        ctx′ = ResolveContext(Ctx, tail = n.joinee)
        return resolve(JoinNode(joinee = ctx.tail, on = n.on, left = n.right, right = n.left, optional = n.optional), ctx′)
    end
    tail′ = resolve(ctx)
    lt = row_type(tail′)
    name = label(n.joinee)
    joinee′ = resolve(n.joinee, ResolveContext(ctx, row_type = lt, implicit_knot = false))
    rt = row_type(joinee′)
    fields = FieldTypeMap()
    for (f, ft) in lt.fields
        fields[f] = ft
    end
    fields[name] = rt
    group = lt.group
    t = RowType(fields, group)
    on′ = resolve_scalar(n.on, ctx, t)
    q′ = RoutedJoin(joinee = joinee′, on = on′, name = name, left = n.left, right = n.right, optional = n.optional, tail = tail′)
    Resolved(t, tail = q′)
end

function resolve(n::LimitNode, ctx)
    tail′ = resolve(ctx)
    if n.offset === nothing && n.limit === nothing
        return tail′
    end
    t = row_type(tail′)
    q′ = Limit(offset = n.offset, limit = n.limit, tail = tail′)
    Resolved(t, tail = q′)
end

function resolve_scalar(n::LiteralNode, ctx)
    Resolved(ScalarType(), tail = convert(SQLQuery, n))
end

function resolve(n::OrderNode, ctx)
    tail′ = resolve(ctx)
    if isempty(n.by)
        return tail′
    end
    t = row_type(tail′)
    by′ = resolve_scalar(n.by, ctx, t)
    q′ = Order(by = by′, tail = tail′)
    Resolved(t, tail = q′)
end

resolve(n::OverNode, ctx) =
    resolve(With(tail = n.arg, args = ctx.tail !== nothing ? SQLQuery[ctx.tail] : SQLQuery[]), ctx)

function resolve(n::PartitionNode, ctx)
    tail′ = resolve(ctx)
    t = row_type(tail′)
    ctx′ = ResolveContext(ctx, row_type = t)
    by′ = resolve_scalar(n.by, ctx′)
    order_by′ = resolve_scalar(n.order_by, ctx′)
    fields = t.fields
    group = t.group
    if n.name === nothing
        group = t
    else
        fields = FieldTypeMap()
        for (f, ft) in t.fields
            if f !== n.name
                fields[f] = ft
            end
        end
        fields[n.name] = RowType(FieldTypeMap(), t)
    end
    q′ = Partition(by = by′, order_by = order_by′, frame = n.frame, name = n.name, tail = tail′)
    Resolved(RowType(fields, group), tail = q′)
end

function resolve(n::SelectNode, ctx)
    tail′ = resolve(ctx)
    t = row_type(tail′)
    args′ = resolve_scalar(n.args, ctx, t)
    fields = FieldTypeMap()
    for (name, i) in n.label_map
        fields[name] = type(args′[i])
    end
    q′ = Select(args = args′, label_map = n.label_map, tail = tail′)
    Resolved(RowType(fields), tail = q′)
end

function resolve_scalar(n::SortNode, ctx)
    tail′ = resolve_scalar(ctx)
    q′ = Sort(value = n.value, nulls = n.nulls, tail = tail′)
    Resolved(type(tail′), tail = q′)
end

function resolve_scalar(n::VariableNode, ctx)
    v = get(ctx.var_types, n.name, nothing)
    if v !== nothing
        depth, t = v
        q′ = BoundVariable(n.name, depth)
        Resolved(t, tail = q′)
    else
        Resolved(ScalarType(), tail = convert(SQLQuery, n))
    end
end

function resolve(n::WhereNode, ctx)
    tail′ = resolve(ctx)
    t = row_type(tail′)
    condition′ = resolve_scalar(n.condition, ctx, t)
    q′ = Where(condition = condition′, tail = tail′)
    Resolved(t, tail = q′)
end

function resolve(n::Union{WithNode, WithExternalNode}, ctx)
    ctx′ = ResolveContext(ctx, knot_type = nothing, implicit_knot = false)
    args′ = resolve(n.args, ctx′)
    cte_types′ = ctx.cte_types
    for (name, i) in n.label_map
        v = get(ctx.cte_types, name, nothing)
        depth = 1 + (v !== nothing ? v[1] : 0)
        t = row_type(args′[i])
        cte_types′ = Base.ImmutableDict(cte_types′, name => (depth, t))
    end
    ctx′ = ResolveContext(ctx, cte_types = cte_types′)
    tail′ = resolve(ctx′)
    if n isa WithNode
        q′ = With(args = args′, materialized = n.materialized, label_map = n.label_map, tail = tail′)
    else
        q′ = WithExternal(args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = n.label_map, tail = tail′)
    end
    Resolved(row_type(tail′), tail = q′)
end
