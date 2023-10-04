# Rewriting the node graph to prepare it for translation.


# Auxiliary nodes.

# A SQL subquery with an undetermined SELECT args.
mutable struct BoxNode <: TabularNode
    over::Union{SQLNode, Nothing}
    type::BoxType
    handle::Int
    refs::Vector{SQLNode}
    imm_refs_begin_at::Union{Int, Nothing}

    BoxNode(; over = nothing, type = EMPTY_BOX, handle = 0, refs = SQLNode[], imm_refs_begin_at = nothing) =
        new(over, type, handle, refs, imm_refs_begin_at)
end

Box(args...; kws...) =
    BoxNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Box), pats::Vector{Any}) =
    dissect(scr, BoxNode, pats)

function PrettyPrinting.quoteof(n::BoxNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Box))
    if !ctx.limit
        if n.type !== EMPTY_BOX
            push!(ex.args, Expr(:kw, :type, quoteof(n.type)))
        end
        if n.handle != 0
            push!(ex.args, Expr(:kw, :handle, n.handle))
        end
        if !isempty(n.refs)
            push!(ex.args, Expr(:kw, :refs, Expr(:vect, quoteof(n.refs, ctx)...)))
        end
        if n.imm_refs_begin_at !== nothing
            push!(ex.args, Expr(:kw, :imm_refs_begin_at, n.imm_refs_begin_at))
        end
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::BoxNode) =
    n.type.name

rebase(n::BoxNode, n′) =
    BoxNode(over = rebase(n.over, n′),
            type = n.type, handle = n.handle, refs = n.refs)

box_type(n::BoxNode) =
    n.type

box_type(n::SQLNode) =
    box_type(n[]::BoxNode)

function reset!(n::BoxNode)
    empty!(n.refs)
    n.imm_refs_begin_at = nothing
end

function begin_imm_refs!(n::BoxNode)
    n.imm_refs_begin_at = length(n.refs) + 1
end

# Get(over = Get(:a), name = :b) => NameBound(over = Get(:b), name = :a)
mutable struct NameBoundNode <: AbstractSQLNode
    over::SQLNode
    name::Symbol

    NameBoundNode(; over, name) =
        new(over, name)
end

NameBound(args...; kws...) =
    NameBoundNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(NameBound), pats::Vector{Any}) =
    dissect(scr, NameBoundNode, pats)

PrettyPrinting.quoteof(n::NameBoundNode, ctx::QuoteContext) =
    Expr(:call, nameof(NameBound), Expr(:kw, :over, quoteof(n.over, ctx)), Expr(:kw, :name, QuoteNode(n.name)))

# Get(over = q, name = :b) => HandleBound(over = Get(:b), handle = get_handle(q))
mutable struct HandleBoundNode <: AbstractSQLNode
    over::SQLNode
    handle::Int

    HandleBoundNode(; over, handle) =
        new(over, handle)
end

HandleBound(args...; kws...) =
    HandleBoundNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(HandleBound), pats::Vector{Any}) =
    dissect(scr, HandleBoundNode, pats)

PrettyPrinting.quoteof(n::HandleBoundNode, ctx::QuoteContext) =
    Expr(:call, nameof(NameBound), Expr(:kw, :over, quoteof(n.over, ctx)), Expr(:kw, :handle, n.handle))

# A generic From node is specialized to FromNothing, FromTable,
# FromReference, FromSelf, FromValues, or FromFunction.
mutable struct FromNothingNode <: TabularNode
end

FromNothing(args...; kws...) =
    FromNothingNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(::FromNothingNode, ::QuoteContext) =
    Expr(:call, nameof(FromNothing))

mutable struct FromTableNode <: TabularNode
    table::SQLTable

    FromTableNode(; table) =
        new(table)
end

FromTable(args...; kws...) =
    FromTableNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::FromTableNode, ctx::QuoteContext)
    tex = get(ctx.vars, n.table, nothing)
    if tex === nothing
        tex = quoteof(n.table, limit = true)
    end
    Expr(:call, nameof(FromTable), Expr(:kw, :table, tex))
end

mutable struct FromReferenceNode <: TabularNode
    over::SQLNode
    name::Symbol

    FromReferenceNode(; over, name) =
        new(over, name)
end

FromReference(args...; kws...) =
    FromReferenceNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromReferenceNode, ctx::QuoteContext) =
    Expr(:call,
         nameof(FromReference),
         Expr(:kw, :over, quoteof(n.over, ctx)),
         Expr(:kw, :name, QuoteNode(n.name)))

mutable struct FromSelfNode <: TabularNode
    over::SQLNode

    FromSelfNode(; over) =
        new(over)
end

FromSelf(args...; kws...) =
    FromSelfNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromSelfNode, ctx::QuoteContext) =
    Expr(:call, nameof(FromSelf), Expr(:kw, :over, quoteof(n.over, ctx)))

mutable struct FromValuesNode <: TabularNode
    columns::NamedTuple

    FromValuesNode(; columns) =
        new(columns)
end

FromValues(args...; kws...) =
    FromValuesNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromValuesNode, ctx::QuoteContext) =
    Expr(:call, nameof(FromValues), Expr(:kw, :columns, quoteof(n.columns, ctx)))

mutable struct FromFunctionNode <: TabularNode
    over::SQLNode
    columns::Vector{Symbol}

    FromFunctionNode(; over, columns) =
        new(over, columns)
end

FromFunction(args...; kws...) =
    FromFunctionNode(args...; kws...) |> SQLNode

PrettyPrinting.quoteof(n::FromFunctionNode, ctx::QuoteContext) =
    Expr(:call,
         nameof(FromFunction),
         Expr(:kw, :over, quoteof(n.over, ctx)),
         Expr(:kw, :columns, Expr(:vect, [QuoteNode(col) for col in n.columns]...)))

# Annotated Bind node.
mutable struct IntBindNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}
    owned::Bool     # Did we find the outer query for this node?

    function IntBindNode(; over = nothing, args, label_map = nothing, owned = false)
        if label_map !== nothing
            new(over, args, label_map, owned)
        else
            n = new(over, args, OrderedDict{Symbol, Int}(), owned)
            populate_label_map!(n)
            n
        end
    end
end

IntBind(args...; kws...) =
    IntBindNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::IntBindNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(IntBind))
    push!(ex.args, Expr(:kw, :args, Expr(:vect, quoteof(n.args, ctx)...)))
    push!(ex.args, Expr(:kw, :owned, n.owned))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

rebase(n::IntBindNode, n′) =
    IntBindNode(over = rebase(n.over, n′),
                     args = n.args, label_map = n.label_map, owned = n.owned)

# A recursive UNION ALL node.
mutable struct KnotNode <: TabularNode
    over::Union{SQLNode, Nothing}
    name::Symbol
    box::BoxNode
    iterator::SQLNode
    iterator_boxes::Vector{BoxNode}

    KnotNode(; over = nothing, iterator, name = label(iterator), iterator_boxes = SQLNode[], box) =
        new(over, name, box, iterator, iterator_boxes)
end

KnotNode(iterator; over = nothing, box) =
    KnotNode(over = over, iterator = iterator, box = box)

Knot(args...; kws...) =
    KnotNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::KnotNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Knot))
    if !ctx.limit
        push!(ex.args, quoteof(n.iterator, ctx))
    else
        push!(ex.args, :…)
    end
    push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
    if !ctx.limit
        box_ex = Expr(:ref, quoteof(SQLNode(n.box), ctx))
        push!(ex.args, Expr(:kw, :box, box_ex))
        push!(ex.args, Expr(:kw, :iterator, quoteof(n.iterator, ctx)))
        iterator_boxes_ex =
            Expr(:vect, Any[Expr(:ref, quoteof(SQLNode(iterator_box), ctx))
                            for iterator_box in n.iterator_boxes]...)
        push!(ex.args, Expr(:kw, :iterator_boxes, iterator_boxes_ex))
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::KnotNode) =
    n.name

rebase(n::KnotNode, n′) =
    KnotNode(over = rebase(n.over, n′),
             name = n.name, box = n.box, iterator = n.iterator, iterator_boxes = n.iterator_boxes)

# Iterate node is split into Knot and IntIterate.
mutable struct IntIterateNode <: TabularNode
    over::Union{SQLNode, Nothing}
    name::Symbol

    IntIterateNode(; over = nothing, name) =
        new(over, name)
end

IntIterate(args...; kws...) =
    IntIterateNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::IntIterateNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(IntIterate))
    push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::IntIterateNode) =
    n.name

rebase(n::IntIterateNode, n′) =
    IntIterateNode(over = rebase(n.over, n′), name = n.name)

# Annotated Join node.
mutable struct IntJoinNode <: TabularNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    left::Bool
    right::Bool
    skip::Bool
    type::BoxType               # Type of the product of `over` and `joinee`.
    lateral::Vector{SQLNode}    # References from `joinee` to `over` for JOIN LATERAL.

    IntJoinNode(; over, joinee, on, left, right, skip, type = EMPTY_BOX, lateral = SQLNode[]) =
        new(over, joinee, on, left, right, skip, type, lateral)
end

IntJoinNode(joinee, on; over = nothing, left = false, right = false, skip = skip, type = EMPTY_BOX, lateral = SQLNode[]) =
    IntJoinNode(over = over, joinee = joinee, on = on, left = left, right = right, skip = skip, type = type, lateral = lateral)

IntJoin(args...; kws...) =
    IntJoinNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::IntJoinNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(IntJoin))
    if !ctx.limit
        push!(ex.args, quoteof(n.joinee, ctx))
        push!(ex.args, quoteof(n.on, ctx))
        if n.left
            push!(ex.args, Expr(:kw, :left, n.left))
        end
        if n.right
            push!(ex.args, Expr(:kw, :right, n.right))
        end
        if n.skip
            push!(ex.args, Expr(:kw, :skip, n.skip))
        end
        if n.type !== EMPTY_BOX
            push!(ex.args, Expr(:kw, :type, n.type))
        end
        if !isempty(n.lateral)
            push!(ex.args, Expr(:kw, :lateral, Expr(:vect, quoteof(n.lateral, ctx)...)))
        end
    else
        push!(ex.args, :…)
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

rebase(n::IntJoinNode, n′) =
    IntJoinNode(over = rebase(n.over, n′),
                     joinee = n.joinee, on = n.on, left = n.left, right = n.right, skip = n.skip, type = n.type, lateral = n.lateral)

# Calculates the keys of a Group node.
mutable struct IntAutoDefineNode <: TabularNode
    over::Union{SQLNode, Nothing}

    IntAutoDefineNode(; over = nothing) =
        new(over)
end

IntAutoDefine(args...; kws...) =
    IntAutoDefineNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::IntAutoDefineNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(IntAutoDefine))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

rebase(n::IntAutoDefineNode, n′) =
    IntAutoDefineNode(over = rebase(n.over, n′))

label(n::Union{NameBoundNode, HandleBoundNode, IntAutoDefineNode, IntBindNode, IntJoinNode}) =
    label(n.over)


# Annotation context.

# Maps a node in the annotated graph to a path in the original graph (for error reporting).
struct PathMap
    paths::Vector{Tuple{SQLNode, Int}}
    origins::IdDict{Any, Int}

    PathMap() =
        new(Tuple{SQLNode, Int}[], IdDict{Any, Int}())
end

function get_path(map::PathMap, idx::Int)
    path = SQLNode[]
    while idx != 0
        n, idx = map.paths[idx]
        push!(path, n)
    end
    path
end

get_path(map::PathMap, n) =
    get_path(map, get(map.origins, n, 0))

struct AnnotateContext
    catalog::SQLCatalog
    path_map::PathMap
    current_path::Vector{Int}
    handles::Dict{SQLNode, Int}
    boxes::Vector{BoxNode}
    with_nodes::Dict{Symbol, SQLNode}
    knot_node::Union{KnotNode, Nothing}
    over_knot::Bool

    AnnotateContext(catalog) =
        new(catalog,
            PathMap(),
            Int[0],
            Dict{SQLNode, Int}(),
            BoxNode[],
            Dict{Symbol, SQLNode}(),
            nothing,
            false)

    AnnotateContext(ctx::AnnotateContext;
                    with_nodes = missing,
                    knot_node = missing,
                    over_knot = missing) =
        new(ctx.catalog,
            ctx.path_map,
            ctx.current_path,
            ctx.handles,
            ctx.boxes,
            coalesce(with_nodes, ctx.with_nodes),
            coalesce(knot_node, ctx.knot_node),
            coalesce(over_knot, ctx.over_knot))
end

function grow_path!(ctx::AnnotateContext, n::SQLNode)
    push!(ctx.path_map.paths, (n, ctx.current_path[end]))
    push!(ctx.current_path, length(ctx.path_map.paths))
end

function shrink_path!(ctx::AnnotateContext)
    pop!(ctx.current_path)
end

function mark_origin!(ctx::AnnotateContext, n::SQLNode)
    ctx.path_map.origins[n] = ctx.current_path[end]
end

mark_origin!(ctx::AnnotateContext, n::AbstractSQLNode) =
    mark_origin!(ctx, convert(SQLNode, n))

get_path(ctx::AnnotateContext) =
    get_path(ctx.path_map, ctx.current_path[end])

get_path(ctx::AnnotateContext, n::SQLNode) =
    get_path(ctx.path_map, n)

function make_handle!(ctx::AnnotateContext, n::SQLNode)
    get!(ctx.handles, n) do
        length(ctx.handles) + 1
    end
end

function get_handle(ctx::AnnotateContext, n::SQLNode)
    handle = 0
    idx = get(ctx.path_map.origins, n, 0)
    if idx > 0
        n = ctx.path_map.paths[idx][1]
        handle = get(ctx.handles, n, 0)
    end
    handle
end

get_handle(ctx::AnnotateContext, ::Nothing) =
    0


# Rewriting of the node graph.

function annotate(n::SQLNode, ctx)
    grow_path!(ctx, n)
    n′ = convert(SQLNode, annotate(n[], ctx))
    mark_origin!(ctx, n′)
    box = BoxNode(over = n′)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(ctx, n′)
    shrink_path!(ctx)
    n′
end

function annotate_scalar(n::SQLNode, ctx)
    grow_path!(ctx, n)
    n′ = convert(SQLNode, annotate_scalar(n[], ctx))
    mark_origin!(ctx, n′)
    shrink_path!(ctx)
    n′
end

annotate(ns::Vector{SQLNode}, ctx) =
    SQLNode[annotate(n, ctx) for n in ns]

annotate_scalar(ns::Vector{SQLNode}, ctx) =
    SQLNode[annotate_scalar(n, ctx) for n in ns]

function annotate(::Nothing, ctx)
    if ctx.over_knot
        knot_node = ctx.knot_node
        @assert knot_node !== nothing
        over = convert(SQLNode, FromSelf(over = knot_node.box))
        mark_origin!(ctx, over)
    else
        over = nothing
    end
    box = BoxNode(over = over)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(ctx, n′)
    n′
end

annotate_scalar(::Nothing, ctx) =
    nothing

annotate(n::AbstractSQLNode, ctx) =
    throw(IllFormedError(path = get_path(ctx)))

function annotate_scalar(n::TabularNode, ctx)
    ctx′ = AnnotateContext(ctx, over_knot = false)
    n′ = convert(SQLNode, annotate(n, ctx′))
    mark_origin!(ctx, n′)
    box = BoxNode(over = n′)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    n′
end

function rebind(node, base, ctx)
    while @dissect(node, over |> Get(name = name))
        mark_origin!(ctx, base)
        base = NameBound(over = base, name = name)
        node = over
    end
    if node !== nothing
        handle = make_handle!(ctx, node)
        mark_origin!(ctx, base)
        base = HandleBound(over = base, handle = handle)
    end
    base
end

function annotate_scalar(n::AggregateNode, ctx)
    args′ = annotate_scalar(n.args, ctx)
    filter′ = annotate_scalar(n.filter, ctx)
    n′ = Agg(name = n.name, args = args′, filter = filter′)
    rebind(n.over, n′, ctx)
end

function annotate(n::AppendNode, ctx)
    over = n.over
    args = n.args
    if over === nothing && !ctx.over_knot
        if !isempty(args)
            over = args[1]
            args = args[2:end]
        else
            over = Where(false)
        end
    end
    over′ = annotate(over, ctx)
    ctx′ = AnnotateContext(ctx, over_knot = false)
    args′ = annotate(args, ctx′)
    Append(over = over′, args = args′)
end

function annotate(n::AsNode, ctx)
    over′ = annotate(n.over, ctx)
    As(over = over′, name = n.name)
end

function annotate_scalar(n::AsNode, ctx)
    over′ = annotate_scalar(n.over, ctx)
    As(over = over′, name = n.name)
end

function annotate(n::BindNode, ctx)
    over′ = annotate(n.over, ctx)
    args′ = annotate_scalar(n.args, ctx)
    IntBind(over = over′, args = args′, label_map = n.label_map)
end

function annotate_scalar(n::BindNode, ctx)
    ctx′ = AnnotateContext(ctx, over_knot = false)
    annotate(n, ctx′)
end

function annotate(n::DefineNode, ctx)
    over′ = annotate(n.over, ctx)
    args′ = annotate_scalar(n.args, ctx)
    Define(over = over′, args = args′, label_map = n.label_map)
end

function annotate(n::FromNode, ctx)
    source = n.source
    if source isa SQLTable
        FromTable(table = source)
    elseif source isa Symbol
        over = get(ctx.with_nodes, source, nothing)
        if over !== nothing
            FromReference(over = over, name = source)
        else
            table = get(ctx.catalog, source, nothing)
            if table !== nothing
                FromTable(table = table)
            else
                throw(ReferenceError(REFERENCE_ERROR_TYPE.UNDEFINED_TABLE_REFERENCE,
                                     name = source,
                                     path = get_path(ctx)))
            end
        end
    elseif source isa SelfSource
        knot_node = ctx.knot_node
        if knot_node !== nothing
            FromSelf(over = knot_node.box)
        else
            throw(ReferenceError(REFERENCE_ERROR_TYPE.INVALID_SELF_REFERENCE,
                                 path = get_path(ctx)))
        end
    elseif source isa ValuesSource
        FromValues(columns = source.columns)
    elseif source isa FunctionSource
        FromFunction(over = annotate_scalar(source.node, ctx),
                     columns = source.columns)
    else
        FromNothing()
    end
end

function annotate_scalar(n::FunctionNode, ctx)
    args′ = annotate_scalar(n.args, ctx)
    Fun(name = n.name, args = args′)
end

function annotate_scalar(n::GetNode, ctx)
    if n.over === nothing
        return n
    end
    rebind(n.over, Get(name = n.name), ctx)
end

function annotate(n::GroupNode, ctx)
    over′ = annotate(n.over, ctx)
    if !isempty(n.by)
        def = IntAutoDefine(over = over′)
        mark_origin!(ctx, def)
        box = BoxNode(over = def)
        push!(ctx.boxes, box)
        over′ = convert(SQLNode, box)
        mark_origin!(ctx, over′)
    end
    by′ = annotate_scalar(n.by, ctx)
    Group(over = over′, by = by′, name = n.name, label_map = n.label_map)
end

function annotate(n::HighlightNode, ctx)
    over′ = annotate(n.over, ctx)
    Highlight(over = over′, color = n.color)
end

function annotate_scalar(n::HighlightNode, ctx)
    over′ = annotate_scalar(n.over, ctx)
    Highlight(over = over′, color = n.color)
end

function annotate(n::IterateNode, ctx)
    over′ = annotate(n.over, ctx)
    knot_box = BoxNode()
    knot = KnotNode(over = over′, iterator = n.iterator, box = knot_box)
    mark_origin!(ctx, knot)
    knot_box.over = knot
    push!(ctx.boxes, knot_box)
    over′ = convert(SQLNode, knot_box)
    mark_origin!(ctx, over′)
    ctx′ = AnnotateContext(ctx, knot_node = knot, over_knot = true)
    range_start = length(ctx.boxes) + 1
    iterator′ = annotate(n.iterator, ctx′)
    range_stop = length(ctx.boxes)
    knot.iterator = iterator′
    knot.iterator_boxes = ctx.boxes[range_start:range_stop]
    IntIterateNode(over = over′, name = label(n.over))
end

function annotate(n::JoinNode, ctx)
    over′ = annotate(n.over, ctx)
    ctx′ = AnnotateContext(ctx, over_knot = false)
    joinee′ = annotate(n.joinee, ctx′)
    on′ = annotate_scalar(n.on, ctx)
    IntJoin(over = over′, joinee = joinee′, on = on′, left = n.left, right = n.right, skip = n.optional)
end

function annotate(n::LimitNode, ctx)
    over′ = annotate(n.over, ctx)
    Limit(over = over′, offset = n.offset, limit = n.limit)
end

annotate_scalar(n::LiteralNode, ctx) =
    n

function annotate(n::OrderNode, ctx)
    over′ = annotate(n.over, ctx)
    by′ = annotate_scalar(n.by, ctx)
    Order(over = over′, by = by′)
end

function annotate(n::PartitionNode, ctx)
    over′ = annotate(n.over, ctx)
    by′ = annotate_scalar(n.by, ctx)
    order_by′ = annotate_scalar(n.order_by, ctx)
    Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame, name = n.name)
end

function annotate(n::SelectNode, ctx)
    over′ = annotate(n.over, ctx)
    args′ = annotate_scalar(n.args, ctx)
    Select(over = over′, args = args′, label_map = n.label_map)
end

function annotate_scalar(n::SortNode, ctx)
    over′ = annotate_scalar(n.over, ctx)
    Sort(over = over′, value = n.value, nulls = n.nulls)
end

annotate_scalar(n::VariableNode, ctx) =
    n

function annotate(n::WhereNode, ctx)
    over′ = annotate(n.over, ctx)
    condition′ = annotate_scalar(n.condition, ctx)
    Where(over = over′, condition = condition′)
end

function annotate(n::WithNode, ctx)
    ctx′ = AnnotateContext(ctx, over_knot = false)
    args′ = annotate(n.args, ctx′)
    with_nodes′ = copy(ctx.with_nodes)
    for (name, i) in n.label_map
        with_nodes′[name] = args′[i]
    end
    ctx′ = AnnotateContext(ctx, with_nodes = with_nodes′)
    over′ = annotate(n.over, ctx′)
    With(over = over′, args = args′, materialized = n.materialized, label_map = n.label_map)
end

function annotate(n::WithExternalNode, ctx)
    ctx′ = AnnotateContext(ctx, over_knot = false)
    args′ = annotate(n.args, ctx′)
    with_nodes′ = copy(ctx.with_nodes)
    for (name, i) in n.label_map
        with_nodes′[name] = args′[i]
    end
    ctx′ = AnnotateContext(ctx, with_nodes = with_nodes′)
    over′ = annotate(n.over, ctx′)
    WithExternal(over = over′, args = args′, qualifiers = n.qualifiers, handler = n.handler, label_map = n.label_map)
end


# Type resolution.

resolve!(ctx::AnnotateContext) =
    resolve!(ctx.boxes, ctx)

function resolve!(boxes::AbstractVector{BoxNode}, ctx)
    for box in boxes
        over = box.over
        if over !== nothing
            h = get_handle(ctx, over)
            t = resolve(over[], ctx)
            t = add_handle(t, h)
            box.handle = h
            box.type = t
        end
    end
end

function resolve(n::AppendNode, ctx)
    t = box_type(n.over)
    for arg in n.args
        t = intersect(t, box_type(arg))
    end
    t
end

function resolve(n::AsNode, ctx)
    t = box_type(n.over)
    fields = FieldTypeMap(n.name => t.row)
    row = RowType(fields)
    BoxType(n.name, row, t.handle_map)
end

function resolve(n::DefineNode, ctx)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for (f, ft) in t.row.fields
        if f in keys(n.label_map)
            ft = ScalarType()
        end
        fields[f] = ft
    end
    for f in keys(n.label_map)
        if !haskey(fields, f)
            fields[f] = ScalarType()
        end
    end
    row = RowType(fields, t.row.group)
    BoxType(t.name, row, t.handle_map)
end

resolve(n::FromNothingNode, ctx) =
    EMPTY_BOX

function resolve(n::FromFunctionNode, ctx)
    fields = FieldTypeMap()
    for f in n.columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(label(n.over), row)
end

function resolve(n::FromReferenceNode, ctx)
    t = box_type(n.over)
    ft = get(t.row.fields, n.name, nothing)
    if !(ft isa RowType)
        throw(ReferenceError(REFERENCE_ERROR_TYPE.INVALID_TABLE_REFERENCE,
                             name = n.name,
                             path = get_path(ctx, n.over)))
    end
    BoxType(n.name, ft)
end

function resolve(n::FromTableNode, ctx)
    fields = FieldTypeMap()
    for f in n.table.columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(n.table.name, row)
end

function resolve(n::FromValuesNode, ctx)
    columns = fieldnames(typeof(n.columns))
    fields = FieldTypeMap()
    for f in columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(:values, row)
end

function resolve(n::GroupNode, ctx)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    if n.name === nothing
        row = RowType(fields, t.row)
    else
        fields[n.name] = RowType(FieldTypeMap(), t.row)
        row = RowType(fields)
    end
    BoxType(t.name, row)
end

resolve(n::Union{FromSelfNode, HighlightNode, IntAutoDefineNode, IntBindNode, KnotNode, LimitNode, OrderNode, WhereNode, WithNode, WithExternalNode}, ctx) =
    box_type(n.over)

resolve_knot!(n::SQLNode, ctx) =
    resolve_knot!(n[], ctx)

function resolve_knot!(n::BoxNode, ctx)
    knot = n.over[]::KnotNode
    iterator_t = box_type(knot.iterator)
    while !issubset(n.type.row, iterator_t.row)
        n.type = intersect(n.type, iterator_t)
        resolve!(knot.iterator_boxes, ctx)
        iterator_t = box_type(knot.iterator)
    end
    n.type = add_handle(n.type, n.handle)
end

function resolve(n::IntIterateNode, ctx)
    resolve_knot!(n.over, ctx)
    t = box_type(n.over)
    BoxType(n.name, t.row)
end

function resolve(n::IntJoinNode, ctx)
    lt = box_type(n.over)
    rt = box_type(n.joinee)
    t = union(lt, rt)
    n.type = t
    t
end

function resolve(n::PartitionNode, ctx)
    t = box_type(n.over)
    if n.name === nothing
        row = RowType(t.row.fields, t.row)
    else
        fields = FieldTypeMap()
        for (f, ft) in t.row.fields
            if f !== n.name
                fields[f] = ft
            end
        end
        fields[n.name] = RowType(FieldTypeMap(), t.row)
        row = RowType(fields, t.row.group)
    end
    BoxType(t.name, row, t.handle_map)
end

function resolve(n::SelectNode, ctx)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    row = RowType(fields)
    BoxType(t.name, row)
end


# Collecting references.

gather!(refs::Vector{SQLNode}, n::SQLNode) =
    gather!(refs, n[])

function gather!(refs::Vector{SQLNode}, ns::Vector{SQLNode})
    for n in ns
        gather!(refs, n)
    end
end

gather!(refs::Vector{SQLNode}, ::Union{AbstractSQLNode, Nothing}) =
    nothing

gather!(refs::Vector{SQLNode}, n::Union{AsNode, BoxNode, FromFunctionNode, HighlightNode, SortNode}) =
    gather!(refs, n.over)

function gather!(refs::Vector{SQLNode}, n::IntBindNode)
    gather!(refs, n.over)
    refs′ = SQLNode[]
    gather!(refs′, n.args)
    append!(refs, refs′)
    # Make sure complex definitions and aggregates are wrapped in a nested
    # subquery.
    append!(refs, refs′)
    n.owned = true
end

gather!(refs::Vector{SQLNode}, n::FunctionNode) =
    gather!(refs, n.args)

function gather!(refs::Vector{SQLNode}, n::Union{AggregateNode, GetNode, HandleBoundNode, NameBoundNode})
    push!(refs, n)
end


# Validating references.

function validate(t::BoxType, ref::SQLNode, ctx)
    if @dissect(ref, over |> HandleBound(handle = handle))
        if handle in keys(t.handle_map)
            ht = t.handle_map[handle]
            if ht isa AmbiguousType
                throw(ReferenceError(REFERENCE_ERROR_TYPE.AMBIGUOUS_HANDLE,
                                     path = get_path(ctx, ref)))
            end
            validate(ht, over, ctx)
        else
            throw(ReferenceError(REFERENCE_ERROR_TYPE.UNDEFINED_HANDLE,
                                 path = get_path(ctx, ref)))
        end
    else
        validate(t.row, ref, ctx)
    end
end

function validate(t::RowType, ref::SQLNode, ctx)
    while @dissect(ref, over |> NameBound(name = name))
        ft = get(t.fields, name, EmptyType())
        if !(ft isa RowType)
            type =
                ft isa EmptyType ? REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                ft isa ScalarType ? REFERENCE_ERROR_TYPE.UNEXPECTED_SCALAR_TYPE :
                ft isa AmbiguousType ? REFERENCE_ERROR_TYPE.AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(ctx, ref)))
        end
        t = ft
        ref = over
    end
    if @dissect(ref, nothing |> Get(name = name))
        ft = get(t.fields, name, EmptyType())
        if !(ft isa ScalarType)
            type =
                ft isa EmptyType ? REFERENCE_ERROR_TYPE.UNDEFINED_NAME :
                ft isa RowType ? REFERENCE_ERROR_TYPE.UNEXPECTED_ROW_TYPE :
                ft isa AmbiguousType ? REFERENCE_ERROR_TYPE.AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(ctx, ref)))
        end
    elseif @dissect(ref, nothing |> Agg(name = name))
        if !(t.group isa RowType)
            type =
                t.group isa EmptyType ? REFERENCE_ERROR_TYPE.UNEXPECTED_AGGREGATE :
                t.group isa AmbiguousType ? REFERENCE_ERROR_TYPE.AMBIGUOUS_AGGREGATE : error()
            throw(ReferenceError(type, path = get_path(ctx, ref)))
        end
    else
        error()
    end
end

function gather_and_validate!(refs::Vector{SQLNode}, n, t::BoxType, ctx)
    start = length(refs) + 1
    gather!(refs, n)
    for k in start:length(refs)
        validate(t, refs[k], ctx)
    end
end

function route(lt::BoxType, rt::BoxType, ref::SQLNode)
    if @dissect(ref, over |> HandleBound(handle = handle))
        if get(lt.handle_map, handle, EmptyType()) isa EmptyType
            return 1
        else
            return -1
        end
    end
    return route(lt.row, rt.row, ref)
end

function route(lt::RowType, rt::RowType, ref::SQLNode)
    while @dissect(ref, over |> NameBound(name = name))
        lt′ = get(lt.fields, name, EmptyType())
        if lt′ isa EmptyType
            return 1
        end
        rt′ = get(rt.fields, name, EmptyType())
        if rt′ isa EmptyType
            return -1
        end
        @assert lt′ isa RowType && rt′ isa RowType
        lt = lt′
        rt = rt′
        ref = over
    end
    if @dissect(ref, Get(name = name))
        if name in keys(lt.fields)
            return -1
        else
            return 1
        end
    elseif @dissect(ref, over |> Agg(name = name))
        if lt.group isa RowType
            return -1
        else
            return 1
        end
    else
        error()
    end
end


# Linking references through box nodes.

function link!(ctx::AnnotateContext)
    root_box = ctx.boxes[end]
    for (f, ft) in root_box.type.row.fields
        if ft isa ScalarType
            push!(root_box.refs, Get(f))
        end
    end
    link!(reverse(ctx.boxes), ctx)
end

function link!(boxes::AbstractVector{BoxNode}, ctx)
    for box in boxes
        box.over !== nothing || continue
        refs′ = SQLNode[]
        for ref in box.refs
            if @dissect(ref, over |> HandleBound(handle = handle)) && handle == box.handle
                push!(refs′, over)
            else
                push!(refs′, ref)
            end
        end
        link!(box.over[], refs′, ctx)
    end
end

function link!(n::AppendNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    for arg in n.args
        box = arg[]::BoxNode
        append!(box.refs, refs)
    end
end

function link!(n::AsNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    for ref in refs
        if @dissect(ref, over |> NameBound(name = name))
            @assert name == n.name
            push!(box.refs, over)
        elseif @dissect(ref, HandleBound())
            push!(box.refs, ref)
        else
            error()
        end
    end
end

function link!(n::DefineNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    seen = Set{Symbol}()
    imm_refs = SQLNode[]
    for ref in refs
        if @dissect(ref, nothing |> Get(name = name)) && name in keys(n.label_map)
            !(name in seen) || continue
            push!(seen, name)
            col = n.args[n.label_map[name]]
            gather_and_validate!(imm_refs, col, box.type, ctx)
        else
            push!(box.refs, ref)
        end
    end
    begin_imm_refs!(box)
    append!(box.refs, imm_refs)
end

link!(::Union{FromFunctionNode, FromNothingNode, FromTableNode, FromValuesNode}, ::Vector{SQLNode}, ctx) =
    nothing

function link!(n::FromReferenceNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    for ref in refs
        push!(box.refs, NameBound(over = ref, name = n.name))
    end
end

function link!(n::Union{FromSelfNode, HighlightNode, IntIterateNode, LimitNode, WithNode, WithExternalNode}, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(n::GroupNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    begin_imm_refs!(box)
    append!(box.refs, n.by)
    has_aggregates = any(ref -> @dissect(ref, Agg() || Agg() |> NameBound()), refs)
    has_aggregates || return
    for ref in refs
        if (@dissect(ref, nothing |> Agg(args = args, filter = filter) |> NameBound(name = name)) && name === n.name) ||
           (@dissect(ref, nothing |> Agg(args = args, filter = filter)) && n.name === nothing)
            gather_and_validate!(box.refs, args, box.type, ctx)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, box.type, ctx)
            end
        elseif @dissect(ref, nothing |> Get(name = name)) && name in keys(n.label_map)
            push!(box.refs, n.by[n.label_map[name]])
        end
    end
end

function link!(n::IntAutoDefineNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    begin_imm_refs!(box)
    gather_and_validate!(box.refs, refs, box.type, ctx)
end

function link!(n::IntBindNode, refs::Vector{SQLNode}, ctx)
    if !n.owned
        gather_and_validate!(SQLNode[], n.args, EMPTY_BOX, ctx)
    end
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(n::IntJoinNode, refs::Vector{SQLNode}, ctx)
    lbox = n.over[]::BoxNode
    rbox = n.joinee[]::BoxNode
    for ref in refs
        turn = route(lbox.type, rbox.type, ref)
        if turn < 0
            push!(lbox.refs, ref)
        else
            push!(rbox.refs, ref)
        end
    end
    if !isempty(rbox.refs)
        n.skip = false
    end
    if n.skip
        return
    end
    begin_imm_refs!(lbox)
    begin_imm_refs!(rbox)
    gather_and_validate!(n.lateral, n.joinee, lbox.type, ctx)
    append!(lbox.refs, n.lateral)
    refs′ = SQLNode[]
    gather_and_validate!(refs′, n.on, n.type, ctx)
    for ref in refs′
        turn = route(lbox.type, rbox.type, ref)
        if turn < 0
            push!(lbox.refs, ref)
        else
            push!(rbox.refs, ref)
        end
    end
end

function link!(n::KnotNode, ::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    iterator_box = n.iterator[]::BoxNode
    refs = SQLNode[]
    seen = Set{SQLNode}()
    while true
        repeat = false
        for ref in n.box.refs
            if !(ref in seen)
                push!(refs, ref)
                push!(seen, ref)
                repeat = true
            end
        end
        reset!(n.box)
        append!(n.box.refs, refs)
        repeat || break
        for ibox in n.iterator_boxes
            reset!(ibox)
        end
        append!(iterator_box.refs, refs)
        link!(reverse(n.iterator_boxes), ctx)
    end
    for ref in refs
        push!(box.refs, ref)
    end
end

function link!(n::OrderNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    begin_imm_refs!(box)
    gather_and_validate!(box.refs, n.by, box.type, ctx)
end

function link!(n::PartitionNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    imm_refs = SQLNode[]
    has_aggregates = false
    for ref in refs
        if (@dissect(ref, nothing |> Agg(args = args, filter = filter) |> NameBound(name = name)) && name === n.name) ||
           (@dissect(ref, nothing |> Agg(args = args, filter = filter)) && n.name === nothing)
            gather_and_validate!(imm_refs, args, box.type, ctx)
            if filter !== nothing
                gather_and_validate!(imm_refs, filter, box.type, ctx)
            end
            has_aggregates = true
        else
            push!(box.refs, ref)
        end
    end
    if has_aggregates
        gather_and_validate!(imm_refs, n.by, box.type, ctx)
        gather_and_validate!(imm_refs, n.order_by, box.type, ctx)
        begin_imm_refs!(box)
        append!(box.refs, imm_refs)
    end
end

function link!(n::SelectNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    begin_imm_refs!(box)
    gather_and_validate!(box.refs, n.args, box.type, ctx)
end

function link!(n::WhereNode, refs::Vector{SQLNode}, ctx)
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    begin_imm_refs!(box)
    gather_and_validate!(box.refs, n.condition, box.type, ctx)
end
