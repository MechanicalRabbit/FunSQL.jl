# Find select lists.

struct LinkContext
    catalog::SQLCatalog
    defs::Vector{SQLNode}
    refs::Vector{SQLNode}
    cte_refs::Base.ImmutableDict{Tuple{Symbol, Int}, Vector{SQLNode}}
    knot_refs::Union{Vector{SQLNode}, Nothing}

    LinkContext(catalog) =
        new(catalog,
            SQLNode[],
            SQLNode[],
            Base.ImmutableDict{Tuple{Symbol, Int}, Vector{SQLNode}}(),
            nothing)

    LinkContext(ctx::LinkContext; refs = ctx.refs, cte_refs = ctx.cte_refs, knot_refs = ctx.knot_refs) =
        new(ctx.catalog,
            ctx.defs,
            refs,
            cte_refs,
            knot_refs)
end

function link(n::SQLNode)
    @dissect(n, WithContext(over = over, catalog = catalog)) || throw(ILLFormedError())
    ctx = LinkContext(catalog)
    t = row_type(over)
    refs = SQLNode[]
    for (f, ft) in t.fields
        if ft isa ScalarType
            push!(refs, Get(f))
        end
    end
    over′ = Linked(refs, over = link(dismantle(over, ctx), ctx, refs))
    WithContext(over = over′, catalog = catalog, defs = ctx.defs)
end

function dismantle(n::SQLNode, ctx)
    convert(SQLNode, dismantle(n[], ctx))
end

function dismantle(ns::Vector{SQLNode}, ctx)
    SQLNode[dismantle(n, ctx) for n in ns]
end

function dismantle_scalar(n::SQLNode, ctx)
    convert(SQLNode, dismantle_scalar(n[], ctx))
end

function dismantle_scalar(ns::Vector{SQLNode}, ctx)
    SQLNode[dismantle_scalar(n, ctx) for n in ns]
end

function dismantle_scalar(n::AggregateNode, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    filter′ = n.filter !== nothing ? dismantle_scalar(n.filter, ctx) : nothing
    Agg(name = n.name, args = args′, filter = filter′)
end

function dismantle(n::AppendNode, ctx)
    over′ = dismantle(n.over, ctx)
    args′ = dismantle(n.args, ctx)
    Append(over = over′, args = args′)
end

function dismantle(n::AsNode, ctx)
    over′ = dismantle(n.over, ctx)
    As(over = over′, name = n.name)
end

function dismantle_scalar(n::AsNode, ctx)
    over′ = dismantle_scalar(n.over, ctx)
    As(over = over′, name = n.name)
end

function dismantle(n::BindNode, ctx)
    over′ = dismantle(n.over, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    BindNode(over = over′, args = args′, label_map = n.label_map)
end

function dismantle_scalar(n::BindNode, ctx)
    over′ = dismantle_scalar(n.over, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    BindNode(over = over′, args = args′, label_map = n.label_map)
end

dismantle_scalar(n::Union{BoundVariableNode, GetNode, LiteralNode, VariableNode}, ctx) =
    convert(SQLNode, n)

function dismantle(n::DefineNode, ctx)
    over′ = dismantle(n.over, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Define(over = over′, args = args′, label_map = n.label_map)
end

function dismantle(n::FromFunctionNode, ctx)
    over′ = dismantle_scalar(n.over, ctx)
    FromFunction(over = over′, columns = n.columns)
end

dismantle(n::Union{FromIterateNode, FromNothingNode, FromTableExpressionNode, FromTableNode, FromValuesNode}, ctx) =
    convert(SQLNode, n)

function dismantle_scalar(n::FunctionNode, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Fun(name = n.name, args = args′)
end

function dismantle(n::GroupNode, ctx)
    over′ = dismantle(n.over, ctx)
    by′ = dismantle_scalar(n.by, ctx)
    Group(over = over′, by = by′, sets = n.sets, name = n.name, label_map = n.label_map)
end

function dismantle(n::IterateNode, ctx)
    over′ = dismantle(n.over, ctx)
    iterator′ = dismantle(n.iterator, ctx)
    Iterate(over = over′, iterator = iterator′)
end

function dismantle(n::JoinNode, ctx)
    rt = row_type(n.joinee)
    router = JoinRouter(Set(keys(rt.fields)), !isa(rt.group, EmptyType))
    over′ = dismantle(n.over, ctx)
    joinee′ = dismantle(n.joinee, ctx)
    on′ = dismantle_scalar(n.on, ctx)
    RoutedJoin(over = over′, joinee = joinee′, on = on′, router = router, left = n.left, right = n.right, optional = n.optional)
end

function dismantle(n::LimitNode, ctx)
    over′ = dismantle(n.over, ctx)
    Limit(over = over′, offset = n.offset, limit = n.limit)
end

function dismantle_scalar(n::NestedNode, ctx)
    over′ = dismantle_scalar(n.over, ctx)
    NestedNode(over = over′, name = n.name)
end

function dismantle(n::OrderNode, ctx)
    over′ = dismantle(n.over, ctx)
    by′ = dismantle_scalar(n.by, ctx)
    Order(over = over′, by = by′)
end

function dismantle(n::PaddingNode, ctx)
    over′ = dismantle(n.over, ctx)
    Padding(over = over′)
end

function dismantle(n::PartitionNode, ctx)
    over′ = dismantle(n.over, ctx)
    by′ = dismantle_scalar(n.by, ctx)
    order_by′  = dismantle_scalar(n.order_by, ctx)
    Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame, name = n.name)
end

dismantle(n::ResolvedNode, ctx) =
    dismantle(n.over, ctx)

function dismantle_scalar(n::ResolvedNode, ctx)
    t = n.type
    if t isa RowType
        n′ = dismantle(n.over, ctx)
        push!(ctx.defs, n′)
        ref = lastindex(ctx.defs)
        Isolated(ref, t)
    else
        dismantle_scalar(n.over, ctx)
    end
end

function dismantle(n::SelectNode, ctx)
    over′ = dismantle(n.over, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Select(over = over′, args = args′, label_map = n.label_map)
end

function dismantle_scalar(n::SortNode, ctx)
    over′ = dismantle_scalar(n.over, ctx)
    Sort(over = over′, value = n.value, nulls = n.nulls)
end

function dismantle(n::WhereNode, ctx)
    over′ = dismantle(n.over, ctx)
    condition′ = dismantle_scalar(n.condition, ctx)
    Where(over = over′, condition = condition′)
end

function dismantle(n::WithNode, ctx)
    over′ = dismantle(n.over, ctx)
    args′ = dismantle(n.args, ctx)
    With(over = over′, args = args′, materialized = n.materialized, label_map = n.label_map)
end

function dismantle(n::WithExternalNode, ctx)
    over′ = dismantle(n.over, ctx)
    args′ = dismantle(n.args, ctx)
    WithExternal(over = over′, args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = n.label_map)
end

function link(n::SQLNode, ctx)
    convert(SQLNode, link(n[], ctx))
end

function link(ns::Vector{SQLNode}, ctx)
    SQLNode[link(n, ctx) for n in ns]
end

link(n, ctx, refs) =
    link(n, LinkContext(ctx, refs = refs))

function link(n::AppendNode, ctx)
    over′ = Linked(ctx.refs, over = link(n.over, ctx))
    args′ = SQLNode[Linked(ctx.refs, over = link(arg, ctx)) for arg in n.args]
    Append(over = over′, args = args′)
end

function link(n::AsNode, ctx)
    refs = SQLNode[]
    for ref in ctx.refs
        if @dissect(ref, over |> Nested(name = name))
            @assert name == n.name
            push!(refs, over)
        else
            error()
        end
    end
    over′ = link(n.over, ctx, refs)
    As(over = over′, name = n.name)
end

function link(n::BindNode, ctx)
    over′ = link(n.over, ctx)
    Bind(over = over′, args = n.args, label_map = n.label_map)
end

function link(n::DefineNode, ctx)
    refs = SQLNode[]
    seen = Set{Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = name)) && name in keys(n.label_map)
            push!(seen, name)
        else
            push!(refs, ref)
        end
    end
    if isempty(seen)
        return link(n.over, ctx)
    end
    n_ext_refs = length(refs)
    args′ = SQLNode[]
    label_map′ = OrderedDict{Symbol, Int}()
    for (f, i) in n.label_map
        f in seen || continue
        arg′ = n.args[i]
        gather!(arg′, ctx, refs)
        push!(args′, arg′)
        label_map′[f] = lastindex(args′)
    end
    over′ = Linked(refs, n_ext_refs, over = link(n.over, ctx, refs))
    Define(
        over = over′,
        args = args′,
        label_map = label_map′)
end

link(n::Union{FromFunctionNode, FromNothingNode, FromTableNode, FromValuesNode}, ctx) =
    convert(SQLNode, n)

function link(n::FromIterateNode, ctx)
    append!(ctx.knot_refs, ctx.refs)
    n
end

function link(n::FromTableExpressionNode, ctx)
    refs = ctx.cte_refs[(n.name, n.depth)]
    for ref in ctx.refs
        push!(refs, Nested(over = ref, name = n.name))
    end
    n
end

function link(n::GroupNode, ctx)
    has_aggregates = any(ref -> @dissect(ref, Agg() || Agg() |> Nested()), ctx.refs)
    if !has_aggregates && isempty(n.by)
        return link(FromNothing(), ctx)
    end
    # Some group keys are added both to SELECT and to GROUP BY.
    # To avoid duplicate SQL, they must be evaluated in a nested subquery.
    refs = SQLNode[]
    append!(refs, n.by)
    if n.sets !== nothing
        # Force evaluation in a nested subquery.
        append!(refs, n.by)
    end
    # Ignore `SELECT DISTINCT` case.
    if has_aggregates
        ctx′ = LinkContext(ctx, refs = refs)
        for ref in ctx.refs
            if (@dissect(ref, nothing |> Agg(args = args, filter = filter) |> Nested(name = name)) && name === n.name) ||
               (@dissect(ref, nothing |> Agg(args = args, filter = filter)) && n.name === nothing)
                gather!(args, ctx′)
                if filter !== nothing
                    gather!(filter, ctx′)
                end
            elseif @dissect(ref, nothing |> Get(name = name)) && name in keys(n.label_map)
                # Force evaluation in a nested subquery.
                push!(refs, n.by[n.label_map[name]])
            end
        end
    end
    over = n.over
    if !isempty(n.by)
        over = Padding(over = over)
    end
    over′ = Linked(refs, 0, over = link(over, ctx, refs))
    Group(over = over′, by = n.by, sets = n.sets, name = n.name, label_map = n.label_map)
end

function link(n::IterateNode, ctx)
    iterator′ = n.iterator
    defs = copy(ctx.defs)
    cte_refs = [(v, length(v)) for (k, v) in ctx.cte_refs]
    refs = SQLNode[]
    knot_refs = SQLNode[]
    repeat = true
    while repeat
        refs = copy(ctx.refs)
        append!(refs, knot_refs)
        knot_refs = SQLNode[]
        for (v, l) in cte_refs
            resize!(v, l)
        end
        iterator′ = link(n.iterator, LinkContext(ctx, refs = refs, knot_refs = knot_refs))
        repeat = false
        seen = Set(refs)
        for ref in knot_refs
            if !in(ref, seen)
                repeat = true
                ctx.defs .= defs
                break
            end
        end
    end
    iterator′ = Linked(refs, over = iterator′)
    over′ = Linked(refs, over = link(n.over, ctx, refs))
    n′ = Linked(refs, over = Iterate(over = over′, iterator = iterator′))
    Padding(over = n′)
end

function route(r::JoinRouter, ref::SQLNode)
    if @dissect(ref, over |> Nested(name = name)) && name in r.label_set
        return 1
    end
    if @dissect(ref, Get(name = name)) && name in r.label_set
        return 1
    end
    if @dissect(ref, over |> Agg()) && r.group
        return 1
    end
    return -1
end

function link(n::RoutedJoinNode, ctx)
    lrefs = SQLNode[]
    rrefs = SQLNode[]
    for ref in ctx.refs
        turn = route(n.router, ref)
        push!(turn < 0 ? lrefs : rrefs, ref)
    end
    if n.optional && isempty(rrefs)
        return link(n.over, ctx)
    end
    ln_ext_refs = length(lrefs)
    rn_ext_refs = length(rrefs)
    refs′ = SQLNode[]
    lateral_refs = SQLNode[]
    gather!(n.joinee, ctx, lateral_refs)
    append!(lrefs, lateral_refs)
    lateral = !isempty(lateral_refs)
    gather!(n.on, ctx, refs′)
    for ref in refs′
        turn = route(n.router, ref)
        push!(turn < 0 ? lrefs : rrefs, ref)
    end
    over′ = Linked(lrefs, ln_ext_refs, over = link(n.over, ctx, lrefs))
    joinee′ = Linked(rrefs, rn_ext_refs, over = link(n.joinee, ctx, rrefs))
    RoutedJoinNode(
        over = over′,
        joinee = joinee′,
        on = n.on,
        router = n.router,
        left = n.left,
        right = n.right,
        lateral = lateral)
end

function link(n::LimitNode, ctx)
    over′ = Linked(ctx.refs, over = link(n.over, ctx))
    Limit(over = over′, offset = n.offset, limit = n.limit)
end

function link(n::OrderNode, ctx)
    refs = copy(ctx.refs)
    n_ext_refs = length(refs)
    gather!(n.by, ctx, refs)
    over′ = Linked(refs, n_ext_refs, over = link(n.over, ctx, refs))
    Order(over = over′, by = n.by)
end

function link(n::PaddingNode, ctx)
    refs = SQLNode[]
    gather!(ctx.refs, ctx, refs)
    over′ = Linked(refs, 0, over = link(n.over, ctx, refs))
    Padding(over = over′)
end

function link(n::PartitionNode, ctx)
    refs = SQLNode[]
    imm_refs = SQLNode[]
    ctx′ = LinkContext(ctx, refs = imm_refs)
    has_aggregates = false
    for ref in ctx.refs
        if (@dissect(ref, nothing |> Agg(args = args, filter = filter) |> Nested(name = name)) && name === n.name) ||
            (@dissect(ref, nothing |> Agg(args = args, filter = filter)) && n.name === nothing)
            gather!(args, ctx′)
            if filter !== nothing
                gather!(filter, ctx′)
            end
            has_aggregates = true
        else
            push!(refs, ref)
        end
    end
    if !has_aggregates
        return link(n.over, ctx)
    end
    gather!(n.by, ctx′)
    gather!(n.order_by, ctx′)
    n_ext_refs = length(refs)
    append!(refs, imm_refs)
    over′ = Linked(refs, n_ext_refs, over = link(n.over, ctx, refs))
    Partition(over = over′, by = n.by, order_by = n.order_by, frame = n.frame, name = n.name)
end

function link(n::SelectNode, ctx)
    refs = SQLNode[]
    gather!(n.args, ctx, refs)
    over′ = Linked(refs, 0, over = link(n.over, ctx, refs))
    Select(over = over′, args = n.args, label_map = n.label_map)
end

function link(n::WhereNode, ctx)
    refs = copy(ctx.refs)
    n_ext_refs = length(refs)
    gather!(n.condition, ctx, refs)
    over′ = Linked(refs, n_ext_refs, over = link(n.over, ctx, refs))
    Where(n.condition, over = over′)
end

function _cte_depth(dict, name)
    for (n, d) in keys(dict)
        if n === name
            return d
        end
    end
    0
end

function link(n::Union{WithNode, WithExternalNode}, ctx)
    cte_refs′ = ctx.cte_refs
    refs_map = Vector{SQLNode}[]
    for name in keys(n.label_map)
        depth = _cte_depth(ctx.cte_refs, name) + 1
        refs = SQLNode[]
        cte_refs′ = Base.ImmutableDict(cte_refs′, (name, depth) => refs)
        push!(refs_map, refs)
    end
    ctx′ = LinkContext(ctx, cte_refs = cte_refs′)
    over′ = Linked(ctx′.refs, over = link(n.over, ctx′))
    args′ = SQLNode[]
    label_map′ = OrderedDict{Symbol, Int}()
    for (f, i) in n.label_map
        arg = n.args[i]
        refs = refs_map[i]
        arg′ = Linked(refs, over = link(arg, ctx, refs))
        push!(args′, arg′)
        label_map′[f] = lastindex(args′)
    end
    if n isa WithNode
        With(over = over′, args = args′, materialized = n.materialized, label_map = label_map′)
    else
        WithExternal(over = over′, args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = label_map′)
    end
end

function gather!(n::SQLNode, ctx)
    gather!(n[], ctx)
end

function gather!(ns::Vector{SQLNode}, ctx)
    for n in ns
        gather!(n, ctx)
    end
end

gather!(n::AbstractSQLNode, ctx) =
    nothing

gather!(n, ctx, refs) =
    gather!(n, LinkContext(ctx, refs = refs))

function gather!(n::Union{AggregateNode, GetNode, NestedNode}, ctx)
    push!(ctx.refs, n)
    nothing
end

function gather!(n::Union{AsNode, FromFunctionNode, ResolvedNode, SortNode}, ctx)
    gather!(n.over, ctx)
end

function gather!(n::BindNode, ctx)
    gather!(n.over, ctx)
    refs′ = SQLNode[]
    gather!(n.args, ctx, refs′)
    append!(ctx.refs, refs′)
    # Force aggregates and other complex definitions to be wrapped
    # in a nested subquery.
    append!(ctx.refs, refs′)
    nothing
end

function gather!(n::FunctionNode, ctx)
    gather!(n.args, ctx)
end

function gather!(n::IsolatedNode, ctx)
    def = ctx.defs[n.idx]
    !@dissect(def, Linked()) || return
    refs = SQLNode[]
    for (f, ft) in n.type.fields
        if ft isa ScalarType
            push!(refs, Get(f))
            break
        end
    end
    def′ = Linked(refs, over = link(def, ctx, refs))
    ctx.defs[n.idx] = def′
    nothing
end
