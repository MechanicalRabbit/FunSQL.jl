# Find select lists.

struct LinkContext
    catalog::SQLCatalog
    tail::Union{SQLQuery, Nothing}
    defs::Vector{SQLQuery}
    refs::Vector{SQLQuery}
    cte_refs::Base.ImmutableDict{Tuple{Symbol, Int}, Vector{SQLQuery}}
    knot_refs::Union{Vector{SQLQuery}, Nothing}

    LinkContext(catalog) =
        new(catalog,
            nothing,
            SQLQuery[],
            SQLQuery[],
            Base.ImmutableDict{Tuple{Symbol, Int}, Vector{SQLQuery}}(),
            nothing)

    LinkContext(ctx::LinkContext; tail = ctx.tail, refs = ctx.refs, cte_refs = ctx.cte_refs, knot_refs = ctx.knot_refs) =
        new(ctx.catalog,
            tail,
            ctx.defs,
            refs,
            cte_refs,
            knot_refs)
end

function _select(t::RowType)
    refs = SQLQuery[]
    t.visible || return refs
    for (f, ft) in t.fields
        if ft isa ScalarType
            ft.visible || continue
            push!(refs, Get(f))
        else
            nested_refs = _select(ft)
            for nested_ref in nested_refs
                push!(refs, Nested(name = f, tail = nested_ref))
            end
        end
    end
    refs
end

function link(q::SQLQuery)
    @dissect(q, (local tail) |> WithContext(catalog = (local catalog))) || throw(IllFormedError())
    ctx = LinkContext(catalog)
    t = row_type(tail)
    refs = _select(t)
    tail′ = Linked(refs, tail = link(dismantle(tail, ctx), ctx, refs))
    WithContext(tail = tail′, catalog = catalog, defs = ctx.defs)
end

function dismantle(q::SQLQuery, ctx)
    convert(SQLQuery, dismantle(q.head, LinkContext(ctx, tail = q.tail)))
end

dismantle(ctx::LinkContext) =
    dismantle(ctx.tail, ctx)

function dismantle(qs::Vector{SQLQuery}, ctx)
    SQLQuery[dismantle(q, ctx) for q in qs]
end

function dismantle_scalar(q::SQLQuery, ctx)
    convert(SQLQuery, dismantle_scalar(q.head, LinkContext(ctx, tail = q.tail)))
end

dismantle_scalar(ctx::LinkContext) =
    dismantle_scalar(ctx.tail, ctx)

function dismantle_scalar(qs::Vector{SQLQuery}, ctx)
    SQLQuery[dismantle_scalar(q, ctx) for q in qs]
end

function dismantle_scalar(n::AggregateNode, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    filter′ = n.filter !== nothing ? dismantle_scalar(n.filter, ctx) : nothing
    Agg(name = n.name, args = args′, filter = filter′)
end

function dismantle(n::AppendNode, ctx)
    tail′ = dismantle(ctx)
    args′ = dismantle(n.args, ctx)
    Append(args = args′, tail = tail′)
end

function dismantle(n::AsNode, ctx)
    tail′ = dismantle(ctx)
    As(name = n.name, tail = tail′)
end

function dismantle_scalar(n::AsNode, ctx)
    tail′ = dismantle_scalar(ctx)
    As(name = n.name, tail = tail′)
end

function dismantle(n::BindNode, ctx)
    tail′ = dismantle(ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Bind(args = args′, label_map = n.label_map, tail = tail′)
end

function dismantle_scalar(n::BindNode, ctx)
    tail′ = dismantle_scalar(ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Bind(args = args′, label_map = n.label_map, tail = tail′)
end

dismantle_scalar(n::Union{BoundVariableNode, GetNode, LiteralNode, VariableNode}, ctx) =
    SQLQuery(ctx.tail, n)

function dismantle(n::DefineNode, ctx)
    tail′ = dismantle(ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Define(args = args′, label_map = n.label_map, tail = tail′)
end

function dismantle(n::FromFunctionNode, ctx)
    tail′ = dismantle_scalar(ctx)
    FromFunction(columns = n.columns, tail = tail′)
end

dismantle(n::Union{FromIterateNode, FromNothingNode, FromTableExpressionNode, FromTableNode, FromValuesNode}, ctx) =
    SQLQuery(ctx.tail, n)

function dismantle_scalar(n::FunctionNode, ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Fun(name = n.name, args = args′)
end

function dismantle(n::GroupNode, ctx)
    tail′ = dismantle(ctx)
    by′ = dismantle_scalar(n.by, ctx)
    Group(by = by′, sets = n.sets, name = n.name, label_map = n.label_map, tail = tail′)
end

function dismantle(n::IntoNode, ctx)
    tail′ = dismantle(ctx)
    Into(name = n.name, tail = tail′)
end

function dismantle(n::IterateNode, ctx)
    tail′ = dismantle(ctx)
    iterator′ = dismantle(n.iterator, ctx)
    Iterate(iterator = iterator′, tail = tail′)
end

function dismantle(n::LimitNode, ctx)
    tail′ = dismantle(ctx)
    Limit(offset = n.offset, limit = n.limit, tail = tail′)
end

function dismantle_scalar(n::NestedNode, ctx)
    tail′ = dismantle_scalar(ctx)
    Nested(name = n.name, tail = tail′)
end

function dismantle(n::OrderNode, ctx)
    tail′ = dismantle(ctx)
    by′ = dismantle_scalar(n.by, ctx)
    Order(by = by′, tail = tail′)
end

function dismantle(n::PaddingNode, ctx)
    tail′ = dismantle(ctx)
    Padding(tail = tail′)
end

function dismantle(n::PartitionNode, ctx)
    tail′ = dismantle(ctx)
    by′ = dismantle_scalar(n.by, ctx)
    order_by′  = dismantle_scalar(n.order_by, ctx)
    Partition(by = by′, order_by = order_by′, frame = n.frame, name = n.name, tail = tail′)
end

dismantle(n::ResolvedNode, ctx) =
    dismantle(ctx)

function dismantle_scalar(n::ResolvedNode, ctx)
    t = n.type
    if t isa RowType
        n′ = dismantle(ctx)
        push!(ctx.defs, n′)
        ref = lastindex(ctx.defs)
        Isolated(ref, t)
    else
        dismantle_scalar(ctx)
    end
end

function dismantle(n::RoutedJoinNode, ctx)
    tail′ = dismantle(ctx)
    joinee′ = dismantle(n.joinee, ctx)
    on′ = dismantle_scalar(n.on, ctx)
    RoutedJoin(joinee = joinee′, on = on′, name = n.name, left = n.left, right = n.right, optional = n.optional, tail = tail′)
end

function dismantle(n::SelectNode, ctx)
    tail′ = dismantle(ctx)
    args′ = dismantle_scalar(n.args, ctx)
    Select(args = args′, label_map = n.label_map, tail = tail′)
end

function dismantle_scalar(n::SortNode, ctx)
    tail′ = dismantle_scalar(ctx)
    Sort(value = n.value, nulls = n.nulls, tail = tail′)
end

function dismantle(n::WhereNode, ctx)
    tail′ = dismantle(ctx)
    condition′ = dismantle_scalar(n.condition, ctx)
    Where(condition = condition′, tail = tail′)
end

function dismantle(n::WithNode, ctx)
    tail′ = dismantle(ctx)
    args′ = dismantle(n.args, ctx)
    With(args = args′, materialized = n.materialized, label_map = n.label_map, tail = tail′)
end

function dismantle(n::WithExternalNode, ctx)
    tail′ = dismantle(ctx)
    args′ = dismantle(n.args, ctx)
    WithExternal(args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = n.label_map, tail = tail′)
end

function link(ctx::LinkContext)
    link(ctx.tail, ctx)
end

function link(q::SQLQuery, ctx)
    convert(SQLQuery, link(q.head, LinkContext(ctx, tail = q.tail)))
end

function link(qs::Vector{SQLQuery}, ctx)
    SQLQuery[link(q, ctx) for q in qs]
end

link(n, ctx, refs) =
    link(n, LinkContext(ctx, refs = refs))

function link(n::AppendNode, ctx)
    tail′ = Linked(ctx.refs, tail = link(ctx))
    args′ = SQLQuery[Linked(ctx.refs, tail = link(arg, ctx)) for arg in n.args]
    Append(args = args′, tail = tail′)
end

function link(n::AsNode, ctx)
    tail′ = link(ctx)
    As(name = n.name, tail = tail′)
end

function link(n::BindNode, ctx)
    tail′ = link(ctx)
    Bind(args = n.args, label_map = n.label_map, tail = tail′)
end

function link(n::DefineNode, ctx)
    refs = SQLQuery[]
    seen = Set{Symbol}()
    for ref in ctx.refs
        if @dissect(ref, nothing |> Get(name = (local name))) && name in keys(n.label_map)
            push!(seen, name)
        else
            push!(refs, ref)
        end
    end
    if isempty(seen)
        return link(ctx)
    end
    n_ext_refs = length(refs)
    args′ = SQLQuery[]
    label_map′ = OrderedDict{Symbol, Int}()
    for (f, i) in n.label_map
        f in seen || continue
        arg′ = n.args[i]
        gather!(arg′, ctx, refs)
        push!(args′, arg′)
        label_map′[f] = lastindex(args′)
    end
    tail′ = Linked(refs, n_ext_refs, tail = link(ctx.tail, ctx, refs))
    Define(
        args = args′,
        label_map = label_map′,
        tail = tail′)
end

link(n::Union{FromFunctionNode, FromNothingNode, FromTableNode, FromValuesNode}, ctx) =
    SQLQuery(ctx.tail, n)

function link(n::FromIterateNode, ctx)
    append!(ctx.knot_refs, ctx.refs)
    n
end

function link(n::FromTableExpressionNode, ctx)
    cte_refs = ctx.cte_refs[(n.name, n.depth)]
    append!(cte_refs, ctx.refs)
    n
end

function link(n::GroupNode, ctx)
    has_aggregates = any(ref -> @dissect(ref, Agg() || Agg() |> Nested()), ctx.refs)
    if !has_aggregates && isempty(n.by)
        return link(FromNothing(), ctx)
    end
    # Some group keys are added both to SELECT and to GROUP BY.
    # To avoid duplicate SQL, they must be evaluated in a nested subquery.
    refs = SQLQuery[]
    append!(refs, n.by)
    if n.sets !== nothing
        # Force evaluation in a nested subquery.
        append!(refs, n.by)
    end
    # Ignore `SELECT DISTINCT` case.
    if has_aggregates
        ctx′ = LinkContext(ctx, refs = refs)
        for ref in ctx.refs
            if (@dissect(ref, nothing |> Agg(args = (local args), filter = (local filter)) |> Nested(name = (local name))) && name === n.name) ||
               (@dissect(ref, nothing |> Agg(args = (local args), filter = (local filter))) && n.name === nothing)
                gather!(args, ctx′)
                if filter !== nothing
                    gather!(filter, ctx′)
                end
            elseif @dissect(ref, nothing |> Get(name = (local name))) && name in keys(n.label_map)
                # Force evaluation in a nested subquery.
                push!(refs, n.by[n.label_map[name]])
            end
        end
    end
    tail = ctx.tail
    if !isempty(n.by)
        tail = Padding(tail = tail)
    end
    tail′ = Linked(refs, 0, tail = link(tail, ctx, refs))
    Group(by = n.by, sets = n.sets, name = n.name, label_map = n.label_map, tail = tail′)
end

function link(n::IntoNode, ctx)
    refs = SQLQuery[]
    for ref in ctx.refs
        if @dissect(ref, (local tail) |> Nested(name = (local name)))
            @assert name == n.name
            push!(refs, tail)
        else
            error()
        end
    end
    tail′ = link(ctx.tail, ctx, refs)
    Into(name = n.name, tail = tail′)
end

function link(n::IterateNode, ctx)
    iterator′ = n.iterator
    defs = copy(ctx.defs)
    cte_refs = [(v, length(v)) for (k, v) in ctx.cte_refs]
    refs = SQLQuery[]
    knot_refs = SQLQuery[]
    repeat = true
    while repeat
        refs = copy(ctx.refs)
        append!(refs, knot_refs)
        knot_refs = SQLQuery[]
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
    iterator′ = Linked(refs, tail = iterator′)
    tail′ = Linked(refs, tail = link(ctx.tail, ctx, refs))
    q′ = Linked(refs, tail = Iterate(iterator = iterator′, tail = tail′))
    Padding(tail = q′)
end

function link(n::LimitNode, ctx)
    tail′ = Linked(ctx.refs, tail = link(ctx))
    Limit(offset = n.offset, limit = n.limit, tail = tail′)
end

function link(n::OrderNode, ctx)
    refs = copy(ctx.refs)
    n_ext_refs = length(refs)
    gather!(n.by, ctx, refs)
    tail′ = Linked(refs, n_ext_refs, tail = link(ctx.tail, ctx, refs))
    Order(by = n.by, tail = tail′)
end

function link(n::PaddingNode, ctx)
    refs = SQLQuery[]
    gather!(ctx.refs, ctx, refs)
    tail′ = Linked(refs, 0, tail = link(ctx.tail, ctx, refs))
    Padding(tail = tail′)
end

function link(n::PartitionNode, ctx)
    refs = SQLQuery[]
    imm_refs = SQLQuery[]
    ctx′ = LinkContext(ctx, refs = imm_refs)
    has_aggregates = false
    for ref in ctx.refs
        if (@dissect(ref, nothing |> Agg(args = (local args), filter = (local filter)) |> Nested(name = (local name))) && name === n.name) ||
            (@dissect(ref, nothing |> Agg(args = (local args), filter = (local filter))) && n.name === nothing)
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
        return link(ctx)
    end
    gather!(n.by, ctx′)
    gather!(n.order_by, ctx′)
    n_ext_refs = length(refs)
    append!(refs, imm_refs)
    tail′ = Linked(refs, n_ext_refs, tail = link(ctx.tail, ctx, refs))
    Partition(by = n.by, order_by = n.order_by, frame = n.frame, name = n.name, tail = tail′)
end

function link(n::RoutedJoinNode, ctx)
    lrefs = SQLQuery[]
    rrefs = SQLQuery[]
    for ref in ctx.refs
        if @dissect(ref, Nested(name = (local name))) && name === n.name
            push!(rrefs, ref)
        else
            push!(lrefs, ref)
        end
    end
    if n.optional && isempty(rrefs)
        return link(ctx)
    end
    ln_ext_refs = length(lrefs)
    rn_ext_refs = length(rrefs)
    refs′ = SQLQuery[]
    lateral_refs = SQLQuery[]
    gather!(n.joinee, ctx, lateral_refs)
    append!(lrefs, lateral_refs)
    lateral = !isempty(lateral_refs)
    gather!(n.on, ctx, refs′)
    for ref in refs′
        if @dissect(ref, Nested(name = (local name))) && name === n.name
            push!(rrefs, ref)
        else
            push!(lrefs, ref)
        end
    end
    tail′ = Linked(lrefs, ln_ext_refs, tail = link(ctx.tail, ctx, lrefs))
    joinee′ = Linked(rrefs, rn_ext_refs, tail = link(Into(name = n.name, tail = n.joinee), ctx, rrefs))
    RoutedJoin(
        joinee = joinee′,
        on = n.on,
        name = n.name,
        left = n.left,
        right = n.right,
        lateral = lateral,
        tail = tail′)
end

function link(n::SelectNode, ctx)
    refs = SQLQuery[]
    gather!(n.args, ctx, refs)
    tail′ = Linked(refs, 0, tail = link(ctx.tail, ctx, refs))
    Select(args = n.args, label_map = n.label_map, tail = tail′)
end

function link(n::WhereNode, ctx)
    refs = copy(ctx.refs)
    n_ext_refs = length(refs)
    gather!(n.condition, ctx, refs)
    tail′ = Linked(refs, n_ext_refs, tail = link(ctx.tail, ctx, refs))
    Where(n.condition, tail = tail′)
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
    refs_map = Vector{SQLQuery}[]
    for name in keys(n.label_map)
        depth = _cte_depth(ctx.cte_refs, name) + 1
        refs = SQLQuery[]
        cte_refs′ = Base.ImmutableDict(cte_refs′, (name, depth) => refs)
        push!(refs_map, refs)
    end
    ctx′ = LinkContext(ctx, cte_refs = cte_refs′)
    tail′ = Linked(ctx′.refs, tail = link(ctx′))
    args′ = SQLQuery[]
    label_map′ = OrderedDict{Symbol, Int}()
    for (f, i) in n.label_map
        arg = n.args[i]
        refs = refs_map[i]
        arg′ = Linked(refs, tail = link(arg, ctx, refs))
        push!(args′, arg′)
        label_map′[f] = lastindex(args′)
    end
    if n isa WithNode
        With(args = args′, materialized = n.materialized, label_map = label_map′, tail = tail′)
    else
        WithExternal(args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = label_map′, tail = tail′)
    end
end

function gather!(q::SQLQuery, ctx)
    if @dissect(q, Agg() || Get() || Nested())
        push!(ctx.refs, q)
    else
        gather!(q.head, LinkContext(ctx, tail = q.tail))
    end
end

function gather!(ctx::LinkContext)
    gather!(ctx.tail, ctx)
end

function gather!(qs::Vector{SQLQuery}, ctx)
    for q in qs
        gather!(q, ctx)
    end
end

gather!(n::AbstractSQLNode, ctx) =
    nothing

gather!(n, ctx, refs) =
    gather!(n, LinkContext(ctx, refs = refs))

function gather!(n::Union{AsNode, FromFunctionNode, ResolvedNode, SortNode}, ctx)
    gather!(ctx)
end

function gather!(n::BindNode, ctx)
    gather!(ctx)
    refs′ = SQLQuery[]
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
    refs = _select(n.type)
    if !isempty(refs)
        refs = refs[1:1]
    end
    def′ = Linked(refs, tail = link(def, ctx, refs))
    ctx.defs[n.idx] = def′
    nothing
end
