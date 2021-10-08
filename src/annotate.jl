# Auxiliary nodes.

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

mutable struct ExtendedJoinNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    joinee::SQLNode
    on::SQLNode
    left::Bool
    right::Bool
    type::BoxType
    lateral::Vector{SQLNode}

    ExtendedJoinNode(; over, joinee, on, left, right, type = EMPTY_BOX, lateral = SQLNode[]) =
        new(over, joinee, on, left, right, type, lateral)
end

ExtendedJoin(args...; kws...) =
    ExtendedJoinNode(args...; kws...) |> SQLNode

label(n::Union{NameBoundNode, HandleBoundNode, ExtendedJoinNode}) =
    label(n.over)

mutable struct BoxNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    type::BoxType
    handle::Int
    refs::Vector{SQLNode}

    BoxNode(; over, type = EMPTY_BOX, handle = 0, refs = SQLNode[]) =
        new(over, type, handle, refs)
end

Box(args...; kws...) =
    BoxNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Box), pats::Vector{Any}) =
    dissect(scr, BoxNode, pats)

function PrettyPrinting.quoteof(n::BoxNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Box))
    push!(ex.args, Expr(:kw, :type, quoteof(n.type)))
    if !isempty(n.refs)
        push!(ex.args, Expr(:kw, :refs, Expr(:vect, quoteof(n.refs, qctx)...)))
    end
    ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    ex
end

label(n::BoxNode) =
    n.type.name

box_type(n::BoxNode) =
    n.type

function box_type(n::SQLNode)
    if @dissect n Box(type = type)
        return type
    else
        error()
    end
end

struct AnnotateContext
    paths::Vector{Tuple{SQLNode, Int}}
    origins::Dict{SQLNode, Int}
    current_path::Vector{Int}
    handles::Dict{SQLNode, Int}
    boxes::Vector{BoxNode}

    AnnotateContext() =
        new(Tuple{SQLNode, Int}[],
            Dict{SQLNode, Int}(),
            Int[0],
            Dict{SQLNode, Int}(),
            BoxNode[])
end

function grow_path!(actx::AnnotateContext, n::SQLNode)
    push!(actx.paths, (n, actx.current_path[end]))
    push!(actx.current_path, length(actx.paths))
end

function shrink_path!(actx::AnnotateContext)
    pop!(actx.current_path)
end

function mark_origin!(actx::AnnotateContext, n::SQLNode)
    actx.origins[n] = actx.current_path[end]
end

mark_origin!(actx::AnnotateContext, n::AbstractSQLNode) =
    mark_origin!(actx, convert(SQLNode, n))

function make_handle!(actx::AnnotateContext, n::SQLNode)
    get!(actx.handles, n) do
        length(actx.handles) + 1
    end
end

function get_handle(actx::AnnotateContext, n::SQLNode)
    handle = 0
    idx = get(actx.origins, n, 0)
    if idx > 0
        n = actx.paths[idx][1]
        handle = get(actx.handles, n, 0)
    end
    handle
end

get_handle(actx::AnnotateContext, ::Nothing) =
    0

get_path(actx::AnnotateContext) =
    get_path(actx, actx.current_path[end])

get_path(actx::AnnotateContext, n::SQLNode) =
    get_path(actx, get(actx.origins, n, 0))

function get_path(actx::AnnotateContext, idx::Int)
    path = SQLNode[]
    while idx != 0
        n, idx = actx.paths[idx]
        push!(path, n)
    end
    path
end

function annotate(actx::AnnotateContext, n::SQLNode)
    grow_path!(actx, n)
    n′ = convert(SQLNode, annotate(actx, n[]))
    mark_origin!(actx, n′)
    box = BoxNode(over = n′)
    push!(actx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(actx, n′)
    shrink_path!(actx)
    n′
end

function annotate_scalar(actx::AnnotateContext, n::SQLNode)
    grow_path!(actx, n)
    n′ = convert(SQLNode, annotate_scalar(actx, n[]))
    mark_origin!(actx, n′)
    shrink_path!(actx)
    n′
end

annotate(actx::AnnotateContext, ns::Vector{SQLNode}) =
    SQLNode[annotate(actx, n) for n in ns]

annotate_scalar(actx::AnnotateContext, ns::Vector{SQLNode}) =
    SQLNode[annotate_scalar(actx, n) for n in ns]

function annotate(actx::AnnotateContext, ::Nothing)
    box = BoxNode(over = nothing)
    push!(actx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(actx, n′)
    n′
end

annotate_scalar(actx::AnnotateContext, ::Nothing) =
    nothing

annotate(actx::AnnotateContext, n::AbstractSQLNode) =
    throw(IllFormedError(path = get_path(actx)))

function annotate_scalar(actx::AnnotateContext, n::SubqueryNode)
    n′ = convert(SQLNode, annotate(actx, n))
    mark_origin!(actx, n′)
    box = BoxNode(over = n′)
    push!(actx.boxes, box)
    n′ = convert(SQLNode, box)
    n′
end

function rebind(actx::AnnotateContext, node, base)
    while @dissect node over |> Get(name = name)
        mark_origin!(actx, base)
        base = NameBound(over = base, name = name)
        node = over
    end
    if node !== nothing
        handle = make_handle!(actx, node)
        mark_origin!(actx, base)
        base = HandleBound(over = base, handle = handle)
    end
    base
end

function annotate_scalar(actx::AnnotateContext, n::AggregateNode)
    args′ = annotate_scalar(actx, n.args)
    filter′ = annotate_scalar(actx, n.filter)
    n′ = Agg(name = n.name, distinct = n.distinct, args = args′, filter = filter′)
    rebind(actx, n.over, n′)
end

function annotate(actx::AnnotateContext, n::AppendNode)
    over′ = annotate(actx, n.over)
    list′ = annotate(actx, n.list)
    Append(over = over′, list = list′)
end

function annotate(actx::AnnotateContext, n::AsNode)
    over′ = annotate(actx, n.over)
    As(over = over′, name = n.name)
end

function annotate_scalar(actx::AnnotateContext, n::AsNode)
    over′ = annotate_scalar(actx, n.over)
    As(over = over′, name = n.name)
end

function annotate(actx::AnnotateContext, n::BindNode)
    over′ = annotate(actx, n.over)
    list′ = annotate_scalar(actx, n.list)
    Bind(over = over′, list = list′)
end

annotate_scalar(actx::AnnotateContext, n::BindNode) =
    annotate(actx, n)

function annotate(actx::AnnotateContext, n::DefineNode)
    over′ = annotate(actx, n.over)
    list′ = annotate_scalar(actx, n.list)
    Define(over = over′, list = list′, label_map = n.label_map)
end

annotate(actx::AnnotateContext, n::FromNode) =
    n

function annotate_scalar(actx::AnnotateContext, n::FunctionNode)
    args′ = annotate_scalar(actx, n.args)
    Fun(name = n.name, args = args′)
end

function annotate_scalar(actx::AnnotateContext, n::GetNode)
    rebind(actx, n.over, Get(name = n.name))
end

function annotate(actx::AnnotateContext, n::GroupNode)
    over′ = annotate(actx, n.over)
    by′ = annotate_scalar(actx, n.by)
    Group(over = over′, by = by′, label_map = n.label_map)
end

function annotate(actx::AnnotateContext, n::HighlightNode)
    over′ = annotate(actx, n.over)
    Highlight(over = over′, color = n.color)
end

function annotate_scalar(actx::AnnotateContext, n::HighlightNode)
    over′ = annotate_scalar(actx, n.over)
    Highlight(over = over′, color = n.color)
end

function annotate(actx::AnnotateContext, n::JoinNode)
    over′ = annotate(actx, n.over)
    joinee′ = annotate(actx, n.joinee)
    on′ = annotate_scalar(actx, n.on)
    ExtendedJoin(over = over′, joinee = joinee′, on = on′, left = n.left, right = n.right)
end

function annotate(actx::AnnotateContext, n::LimitNode)
    over′ = annotate(actx, n.over)
    Limit(over = over′, offset = n.offset, limit = n.limit)
end

annotate_scalar(actx::AnnotateContext, n::LiteralNode) =
    n

function annotate(actx::AnnotateContext, n::OrderNode)
    over′ = annotate(actx, n.over)
    by′ = annotate_scalar(actx, n.by)
    Order(over = over′, by = by′)
end

function annotate(actx::AnnotateContext, n::PartitionNode)
    over′ = annotate(actx, n.over)
    by′ = annotate_scalar(actx, n.by)
    order_by′ = annotate_scalar(actx, n.order_by)
    Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame)
end

function annotate(actx::AnnotateContext, n::SelectNode)
    over′ = annotate(actx, n.over)
    list′ = annotate_scalar(actx, n.list)
    Select(over = over′, list = list′, label_map = n.label_map)
end

function annotate_scalar(actx::AnnotateContext, n::SortNode)
    over′ = annotate_scalar(actx, n.over)
    Sort(over = over′, value = n.value, nulls = n.nulls)
end

annotate_scalar(actx::AnnotateContext, n::VariableNode) =
    n

function annotate(actx::AnnotateContext, n::WhereNode)
    over′ = annotate(actx, n.over)
    condition′ = annotate_scalar(actx, n.condition)
    Where(over = over′, condition = condition′)
end

# Type resolution.

function resolve!(actx::AnnotateContext)
    for box in actx.boxes
        over = box.over
        if over !== nothing
            h = get_handle(actx, over)
            t = resolve(actx, over[])
            t = add_handle(t, h)
            box.handle = h
            box.type = t
        end
    end
end

function resolve(actx::AnnotateContext, n::AppendNode)
    t = box_type(n.over)
    for m in n.list
        t = intersect(t, box_type(m))
    end
    t
end

function resolve(actx::AnnotateContext, n::AsNode)
    t = box_type(n.over)
    fields = OrderedDict{Symbol, AbstractSQLType}(n.name => t.row)
    row = RowType(fields)
    BoxType(n.name, row, t.handle_map)
end

resolve(actx::AnnotateContext, n::Union{BindNode, HighlightNode, LimitNode, OrderNode, WhereNode}) =
    box_type(n.over)

function resolve(actx::AnnotateContext, n::DefineNode)
    t = box_type(n.over)
    fields = OrderedDict{Symbol, AbstractSQLType}()
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
    row = RowType(fields)
    BoxType(t.name, row, t.handle_map)
end

function resolve(actx::AnnotateContext, n::ExtendedJoinNode)
    lt = box_type(n.over)
    rt = box_type(n.joinee)
    t = union(lt, rt)
    n.type = t
    t
end

function resolve(actx::AnnotateContext, n::FromNode)
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for f in n.table.columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(n.table.name, row)
end

function resolve(actx::AnnotateContext, n::GroupNode)
    t = box_type(n.over)
    fields = Dict{Symbol, AbstractSQLType}()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    row = RowType(fields, t.row)
    BoxType(t.name, row)
end

function resolve(actx::AnnotateContext, n::PartitionNode)
    t = box_type(n.over)
    row = RowType(t.row.fields, t.row)
    BoxType(t.name, row, t.handle_map)
end

function resolve(actx::AnnotateContext, n::SelectNode)
    t = box_type(n.over)
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    row = RowType(fields)
    BoxType(t.name, row)
end

