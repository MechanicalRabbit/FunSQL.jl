# Resolving node types.

struct ResolveContext
    dialect::SQLDialect
    tables::Dict{Symbol, SQLTable}
    path::Vector{SQLNode}
    row_type::RowType
    cte_types::Dict{Symbol, RowType}
    knot_type::Union{RowType, Nothing}
    implicit_knot::Bool

    ResolveContext(dialect, tables) =
        new(dialect,
            tables,
            SQLNode[],
            EMPTY_ROW,
            Dict{Symbol, RowType}(),
            nothing,
            false)

    ResolveContext(
            ctx::ResolveContext;
            row_type = missing,
            cte_types = missing,
            knot_type = missing,
            implicit_knot = missing) =
        new(ctx.dialect,
            ctx.tables,
            ctx.path,
            coalesce(row_type, ctx.row_type),
            coalesce(cte_types, ctx.cte_types),
            coalesce(knot_type, ctx.knot_type),
            coalesce(implicit_knot, ctx.implicit_knot))
end

get_path(ctx::ResolveContext) =
    copy(ctx.path)

function row_type(n::SQLNode)
    @dissect(n, Resolved(type = type::RowType)) || throw(IllFormedError())
    type
end

function type(n::SQLNode)
    @dissect(n, Resolved(type = t)) || throw(IllFormedError())
    t
end

function resolve(n::SQLNode)
    @dissect(n, WithContext(over = n′, dialect = dialect, tables = tables)) || throw(IllFormedError())
    ctx = ResolveContext(dialect, tables)
    WithContext(over = resolve(n′, ctx), dialect = dialect)
end

function resolve(n::SQLNode, ctx)
    push!(ctx.path, n)
    try
        convert(SQLNode, resolve(n[], ctx))
    finally
        pop!(ctx.path)
    end
end

resolve(ns::Vector{SQLNode}, ctx) =
    SQLNode[resolve(n, ctx) for n in ns]

function resolve(::Nothing, ctx)
    t = ctx.knot_type
    if t !== nothing && ctx.implicit_knot
        n = FromKnot()
    else
        n = FromNothing()
        t = EMPTY_ROW
    end
    Resolved(t, over = n)
end

resolve(n, ctx, t) =
    resolve(n, ResolveContext(ctx, row_type = t))

resolve(n::AbstractSQLNode, ctx) =
    throw(IllFormedError(path = get_path(ctx)))

function resolve_scalar(n::SQLNode, ctx)
    push!(ctx.path, n)
    n′ = convert(SQLNode, resolve_scalar(n[], ctx))
    pop!(ctx.path)
    n′
end

function resolve_scalar(ns::Vector{SQLNode}, ctx)
    SQLNode[resolve_scalar(n, ctx) for n in ns]
end

resolve_scalar(n, ctx, t) =
    resolve_scalar(n, ResolveContext(ctx, row_type = t))

function resolve_scalar(n::TabularNode, ctx)
    n′ = resolve(n, ResolveContext(ctx, implicit_knot = false))
    Resolved(ScalarType(), over = n′)
end

function rebind(node, base, ctx)
    while @dissect(node, over |> Get(name = name))
        base = Bound(over = base, name = name)
        node = over
    end
    if node !== nothing
        throw(IllFormedError(path = get_path(ctx)))
    end
    base
end

function resolve_scalar(n::AggregateNode, ctx)
    if n.over !== nothing
        n′ = rebind(n.over, Agg(name = n.name, args = n.args, filter = n.filter), ctx)
        return resolve_scalar(n′, ctx)
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
    n′ = Agg(name = n.name, args = args′, filter = filter′)
    Resolved(ScalarType(), over = n′)
end

function resolve(n::AppendNode, ctx)
    over = n.over
    args = n.args
    if over === nothing && !ctx.implicit_knot
        if !isempty(args)
            over = args[1]
            args = args[2:end]
        else
            over = Where(false)
        end
    end
    over′ = resolve(over, ctx)
    args′ = resolve(args, ResolveContext(ctx, implicit_knot = false))
    n′ = Append(over = over′, args = args′)
    t = row_type(over′)
    for arg in args′
        t = intersect(t, row_type(arg))
    end
    Resolved(t, over = n′)
end

function resolve(n::AsNode, ctx)
    over′ = resolve(n.over, ctx)
    t = row_type(over′)
    n′ = As(name = n.name, over = over′)
    Resolved(RowType(FieldTypeMap(n.name => t)), over = n′)
end

function resolve_scalar(n::AsNode, ctx)
    over′ = resolve_scalar(n.over, ctx)
    n′ = As(name = n.name, over = over′)
    Resolved(type(over′), over = n′)
end

function resolve(n::BindNode, ctx)
    args′ = resolve_scalar(n.args, ctx)
    over′ = resolve(n.over, ctx)
    n′ = Bind(over = over′, args = args′, label_map = n.label_map)
    Resolved(row_type(over′), over = n′)
end

function resolve_scalar(n::BindNode, ctx)
    args′ = resolve_scalar(n.args, ctx)
    over′ = resolve_scalar(n.over, ctx)
    n′ = Bind(over = over′, args = args′, label_map = n.label_map)
    Resolved(type(over′), over = n′)
end

function resolve_scalar(n::BoundNode, ctx)
    t = get(ctx.row_type.fields, n.name, EmptyType())
    if !(t isa RowType)
        error_type =
            t isa EmptyType ?
                REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE
        throw(ReferenceError(error_type, name = n.name, path = get_path(ctx)))
    end
    over′ = resolve_scalar(n.over, ctx, t)
    n′ = BoundNode(over = over′, name = n.name)
    Resolved(type(over′), over = n′)
end

function resolve(n::DefineNode, ctx)
    over′ = resolve(n.over, ctx)
    t = row_type(over′)
    args′ = resolve_scalar(n.args, ctx, t)
    fields = FieldTypeMap()
    for (f, ft) in t.fields
        i = get(n.label_map, f, nothing)
        if i !== nothing
            ft = type(args′[i])
        end
        fields[f] = ft
    end
    for (f, i) in n.label_map
        if !haskey(fields, f)
            fields[f] = type(args′[i])
        end
    end
    n′ = Define(over = over′, args = args′, label_map = n.label_map)
    Resolved(RowType(fields, t.group), over = n′)
end

function RowType(table::SQLTable)
    fields = FieldTypeMap()
    for f in table.columns
        fields[f] = ScalarType()
    end
    RowType(fields)
end

function resolve(n::FromNode, ctx)
    source = n.source
    if source isa SQLTable
        n′ = FromTable(table = source)
        t = RowType(source)
    elseif source isa Symbol
        t = get(ctx.cte_types, source, nothing)
        if t !== nothing
            n′ = FromReference(source)
        else
            table = get(ctx.tables, source, nothing)
            if table === nothing
                throw(
                    ReferenceError(
                        REFERENCE_ERROR_TYPE.UNDEFINED_TABLE_REFERENCE,
                        name = source,
                        path = get_path(ctx)))
            end
            n′ = FromTable(table = table)
            t = RowType(table)
        end
    elseif source isa KnotSource
        t = ctx.knot_type
        if t === nothing
            throw(
                ReferenceError(
                    REFERENCE_ERROR_TYPE.INVALID_SELF_REFERENCE,
                    path = get_path(ctx)))
        end
        n′ = FromKnot()
    elseif source isa ValuesSource
        n′ = FromValues(columns = source.columns)
        fields = FieldTypeMap()
        for f in keys(source.columns)
            fields[f] = ScalarType()
        end
        t = RowType(fields)
    elseif source isa FunctionSource
        n′ = FromFunction(over = resolve_scalar(source.node, ctx), columns = source.columns)
        fields = FieldTypeMap()
        for f in source.columns
            fields[f] = ScalarType()
        end
        t = RowType(fields)
    elseif source === nothing
        n′ = FromNothing()
        t = RowType()
    else
        error()
    end
    Resolved(t, over = n′)
end

function resolve_scalar(n::FunctionNode, ctx)
    args′ = resolve_scalar(n.args, ctx)
    n′ = Fun(name = n.name, args = args′)
    Resolved(ScalarType(), over = n′)
end

function resolve_scalar(n::GetNode, ctx)
    if n.over !== nothing
        n′ = rebind(n.over, Get(name = n.name), ctx)
        return resolve_scalar(n′, ctx)
    end
    t = get(ctx.row_type.fields, n.name, EmptyType())
    if !(t isa ScalarType)
        error_type =
            t isa EmptyType ?
                REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE
        throw(ReferenceError(error_type, name = n.name, path = get_path(ctx)))
    end
    Resolved(t, over = n)
end

function resolve(n::GroupNode, ctx)
    over′ = resolve(n.over, ctx)
    t = row_type(over′)
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
    n′ = Group(over = over′, by = by′, label_map = n.label_map)
    Resolved(RowType(fields, group), over = n′)
end

resolve(n::HighlightNode, ctx) =
    resolve(n.over, ctx)

resolve_scalar(n::HighlightNode, ctx) =
    resolve_scalar(n.over, ctx)

function resolve(n::IterateNode, ctx)
    over′ = resolve(n.over, ResolveContext(ctx, knot_type = nothing, implicit_knot = false))
    t = row_type(over′)
    iterator′ = resolve(n.iterator, ResolveContext(ctx, knot_type = t, implicit_knot = true))
    iterator_t = row_type(iterator′)
    while !issubset(t, iterator_t)
        t = intersect(t, iterator_t)
        iterator′ = resolve(n.iterator, ResolveContext(ctx, knot_type = t, implicit_knot = true))
        iterator_t = row_type(iterator′)
    end
    n′ = IterateNode(over = over′, iterator = iterator′)
    Resolved(t, over = n′)
end

function resolve(n::JoinNode, ctx)
    over′ = resolve(n.over, ctx)
    lt = row_type(over′)
    joinee′ = resolve(n.joinee, ResolveContext(ctx, row_type = lt, implicit_knot = false))
    rt = row_type(joinee′)
    fields = FieldTypeMap()
    for (f, ft) in lt.fields
        fields[f] = get(rt.fields, f, ft)
    end
    for (f, ft) in rt.fields
        if !haskey(fields, f)
            fields[f] = ft
        end
    end
    group = rt.group isa EmptyType ? lt.group : rt.group
    t = RowType(fields, group)
    on′ = resolve_scalar(n.on, ctx, t)
    n′ = Join(over = over′, joinee = joinee′, on = on′, left = n.left, right = n.right, optional = n.optional)
    Resolved(t, over = n′)
end

function resolve(n::LimitNode, ctx)
    over′ = resolve(n.over, ctx)
    if n.offset === nothing && n.limit === nothing
        return over′
    end
    t = row_type(over′)
    n′ = Limit(over = over′, offset = n.offset, limit = n.limit)
    Resolved(t, over = n′)
end

function resolve_scalar(n::LiteralNode, ctx)
    Resolved(ScalarType(), over = n)
end

function resolve(n::OrderNode, ctx)
    over′ = resolve(n.over, ctx)
    if isempty(n.by)
        return over′
    end
    t = row_type(over′)
    by′ = resolve_scalar(n.by, ctx, t)
    n′ = Order(over = over′, by = by′)
    Resolved(t, over = n′)
end

resolve(n::OverNode, ctx) =
    resolve(With(over = n.arg, args = n.over !== nothing ? SQLNode[n.over] : SQLNode[]), ctx)

function resolve(n::PartitionNode, ctx)
    over′ = resolve(n.over, ctx)
    t = row_type(over′)
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
    n′ = Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame, name = n.name)
    Resolved(RowType(fields, group), over = n′)
end

function resolve(n::SelectNode, ctx)
    over′ = resolve(n.over, ctx)
    t = row_type(over′)
    args′ = resolve_scalar(n.args, ctx, t)
    fields = FieldTypeMap()
    for (name, i) in n.label_map
        fields[name] = type(args′[i])
    end
    n′ = Select(over = over′, args = args′, label_map = n.label_map)
    Resolved(RowType(fields), over = n′)
end

function resolve_scalar(n::SortNode, ctx)
    over′ = resolve_scalar(n.over, ctx)
    n′ = Sort(over = over′, value = n.value, nulls = n.nulls)
    Resolved(type(over′), over = n′)
end

function resolve_scalar(n::VariableNode, ctx)
    Resolved(ScalarType(), over = n)
end

function resolve(n::WhereNode, ctx)
    over′ = resolve(n.over, ctx)
    t = row_type(over′)
    condition′ = resolve_scalar(n.condition, ctx, t)
    n′ = Where(over = over′, condition = condition′)
    Resolved(t, over = n′)
end

function resolve(n::WithNode, ctx)
    ctx′ = ResolveContext(ctx, knot_type = nothing, implicit_knot = false)
    args′ = resolve(n.args, ctx′)
    cte_types = copy(ctx.cte_types)
    for (name, i) in n.label_map
        @assert !in(name, keys(cte_types)) "TODO: CTE shadowing"
        t = row_type(args′[i])
        cte_t = get(t.fields, name, EmptyType())
        if !(cte_t isa RowType)
            throw(
                ReferenceError(
                    REFERENCE_ERROR_TYPE.INVALID_TABLE_REFERENCE,
                    name = name,
                    path = get_path(ctx)))

        end
        cte_types[name] = cte_t
    end
    ctx′ = ResolveContext(ctx, cte_types = cte_types)
    over′ = resolve(n.over, ctx′)
    n′ = With(over = over′, args = args′, materialized = n.materialized, label_map = n.label_map)
    Resolved(row_type(over′), over = n′)
end

function resolve(n::WithExternalNode, ctx)
    ctx′ = ResolveContext(ctx, knot_type = nothing, implicit_knot = false)
    args′ = resolve(n.args, ctx′)
    cte_types = copy(ctx.cte_types)
    for (name, i) in n.label_map
        t = row_type(args′[i])
        cte_t = get(t.fields, name, EmptyType())
        if !(cte_t isa RowType)
            throw(
                ReferenceError(
                    REFERENCE_ERROR_TYPE.INVALID_TABLE_REFERENCE,
                    name = name,
                    path = get_path(ctx)))

        end
        cte_types[name] = cte_t
    end
    ctx′ = ResolveContext(ctx, cte_types = cte_types)
    over′ = resolve(n.over, ctx′)
    n′ = WithExternal(over = over′, args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = n.label_map)
    Resolved(row_type(over′), over = n′)
end
