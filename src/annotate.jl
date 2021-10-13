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


mutable struct ExtendedBindNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}
    owned::Bool

    ExtendedBindNode(; over = nothing, list, label_map, owned = false) =
        new(over, list, label_map, owned)
end

ExtendedBind(args...; kws...) =
    ExtendedBindNode(args...; kws...) |> SQLNode

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

label(n::Union{NameBoundNode, HandleBoundNode, ExtendedBindNode, ExtendedJoinNode}) =
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
    path_map::PathMap
    current_path::Vector{Int}
    handles::Dict{SQLNode, Int}
    boxes::Vector{BoxNode}

    AnnotateContext() =
        new(PathMap(), Int[0], Dict{SQLNode, Int}(), BoxNode[])
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

function annotate(ctx::AnnotateContext, n::SQLNode)
    grow_path!(ctx, n)
    n′ = convert(SQLNode, annotate(ctx, n[]))
    mark_origin!(ctx, n′)
    box = BoxNode(over = n′)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(ctx, n′)
    shrink_path!(ctx)
    n′
end

function annotate_scalar(ctx::AnnotateContext, n::SQLNode)
    grow_path!(ctx, n)
    n′ = convert(SQLNode, annotate_scalar(ctx, n[]))
    mark_origin!(ctx, n′)
    shrink_path!(ctx)
    n′
end

annotate(ctx::AnnotateContext, ns::Vector{SQLNode}) =
    SQLNode[annotate(ctx, n) for n in ns]

annotate_scalar(ctx::AnnotateContext, ns::Vector{SQLNode}) =
    SQLNode[annotate_scalar(ctx, n) for n in ns]

function annotate(ctx::AnnotateContext, ::Nothing)
    box = BoxNode(over = nothing)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    mark_origin!(ctx, n′)
    n′
end

annotate_scalar(ctx::AnnotateContext, ::Nothing) =
    nothing

annotate(ctx::AnnotateContext, n::AbstractSQLNode) =
    throw(IllFormedError(path = get_path(ctx)))

function annotate_scalar(ctx::AnnotateContext, n::SubqueryNode)
    n′ = convert(SQLNode, annotate(ctx, n))
    mark_origin!(ctx, n′)
    box = BoxNode(over = n′)
    push!(ctx.boxes, box)
    n′ = convert(SQLNode, box)
    n′
end

function rebind(ctx::AnnotateContext, node, base)
    while @dissect node over |> Get(name = name)
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

function annotate_scalar(ctx::AnnotateContext, n::AggregateNode)
    args′ = annotate_scalar(ctx, n.args)
    filter′ = annotate_scalar(ctx, n.filter)
    n′ = Agg(name = n.name, distinct = n.distinct, args = args′, filter = filter′)
    rebind(ctx, n.over, n′)
end

function annotate(ctx::AnnotateContext, n::AppendNode)
    over′ = annotate(ctx, n.over)
    list′ = annotate(ctx, n.list)
    Append(over = over′, list = list′)
end

function annotate(ctx::AnnotateContext, n::AsNode)
    over′ = annotate(ctx, n.over)
    As(over = over′, name = n.name)
end

function annotate_scalar(ctx::AnnotateContext, n::AsNode)
    over′ = annotate_scalar(ctx, n.over)
    As(over = over′, name = n.name)
end

function annotate(ctx::AnnotateContext, n::BindNode)
    over′ = annotate(ctx, n.over)
    list′ = annotate_scalar(ctx, n.list)
    ExtendedBind(over = over′, list = list′, label_map = n.label_map)
end

annotate_scalar(ctx::AnnotateContext, n::BindNode) =
    annotate(ctx, n)

function annotate(ctx::AnnotateContext, n::DefineNode)
    over′ = annotate(ctx, n.over)
    list′ = annotate_scalar(ctx, n.list)
    Define(over = over′, list = list′, label_map = n.label_map)
end

annotate(ctx::AnnotateContext, n::FromNode) =
    n

function annotate_scalar(ctx::AnnotateContext, n::FunctionNode)
    args′ = annotate_scalar(ctx, n.args)
    Fun(name = n.name, args = args′)
end

function annotate_scalar(ctx::AnnotateContext, n::GetNode)
    rebind(ctx, n.over, Get(name = n.name))
end

function annotate(ctx::AnnotateContext, n::GroupNode)
    over′ = annotate(ctx, n.over)
    by′ = annotate_scalar(ctx, n.by)
    Group(over = over′, by = by′, label_map = n.label_map)
end

function annotate(ctx::AnnotateContext, n::HighlightNode)
    over′ = annotate(ctx, n.over)
    Highlight(over = over′, color = n.color)
end

function annotate_scalar(ctx::AnnotateContext, n::HighlightNode)
    over′ = annotate_scalar(ctx, n.over)
    Highlight(over = over′, color = n.color)
end

function annotate(ctx::AnnotateContext, n::JoinNode)
    over′ = annotate(ctx, n.over)
    joinee′ = annotate(ctx, n.joinee)
    on′ = annotate_scalar(ctx, n.on)
    ExtendedJoin(over = over′, joinee = joinee′, on = on′, left = n.left, right = n.right)
end

function annotate(ctx::AnnotateContext, n::LimitNode)
    over′ = annotate(ctx, n.over)
    Limit(over = over′, offset = n.offset, limit = n.limit)
end

annotate_scalar(ctx::AnnotateContext, n::LiteralNode) =
    n

function annotate(ctx::AnnotateContext, n::OrderNode)
    over′ = annotate(ctx, n.over)
    by′ = annotate_scalar(ctx, n.by)
    Order(over = over′, by = by′)
end

function annotate(ctx::AnnotateContext, n::PartitionNode)
    over′ = annotate(ctx, n.over)
    by′ = annotate_scalar(ctx, n.by)
    order_by′ = annotate_scalar(ctx, n.order_by)
    Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame)
end

function annotate(ctx::AnnotateContext, n::SelectNode)
    over′ = annotate(ctx, n.over)
    list′ = annotate_scalar(ctx, n.list)
    Select(over = over′, list = list′, label_map = n.label_map)
end

function annotate_scalar(ctx::AnnotateContext, n::SortNode)
    over′ = annotate_scalar(ctx, n.over)
    Sort(over = over′, value = n.value, nulls = n.nulls)
end

annotate_scalar(ctx::AnnotateContext, n::VariableNode) =
    n

function annotate(ctx::AnnotateContext, n::WhereNode)
    over′ = annotate(ctx, n.over)
    condition′ = annotate_scalar(ctx, n.condition)
    Where(over = over′, condition = condition′)
end

# Type resolution.

function resolve!(ctx::AnnotateContext)
    for box in ctx.boxes
        over = box.over
        if over !== nothing
            h = get_handle(ctx, over)
            t = resolve(ctx, over[])
            t = add_handle(t, h)
            box.handle = h
            box.type = t
        end
    end
end

function resolve(ctx::AnnotateContext, n::AppendNode)
    t = box_type(n.over)
    for m in n.list
        t = intersect(t, box_type(m))
    end
    t
end

function resolve(ctx::AnnotateContext, n::AsNode)
    t = box_type(n.over)
    fields = FieldTypeMap(n.name => t.row)
    row = RowType(fields)
    BoxType(n.name, row, t.handle_map)
end

function resolve(ctx::AnnotateContext, n::DefineNode)
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
    row = RowType(fields)
    BoxType(t.name, row, t.handle_map)
end

resolve(ctx::AnnotateContext, n::Union{ExtendedBindNode, HighlightNode, LimitNode, OrderNode, WhereNode}) =
    box_type(n.over)

function resolve(ctx::AnnotateContext, n::ExtendedJoinNode)
    lt = box_type(n.over)
    rt = box_type(n.joinee)
    t = union(lt, rt)
    n.type = t
    t
end

function resolve(ctx::AnnotateContext, n::FromNode)
    fields = FieldTypeMap()
    for f in n.table.columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(n.table.name, row)
end

function resolve(ctx::AnnotateContext, n::GroupNode)
    t = box_type(n.over)
    fields = FieldTypeMap()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    row = RowType(fields, t.row)
    BoxType(t.name, row)
end

function resolve(ctx::AnnotateContext, n::PartitionNode)
    t = box_type(n.over)
    row = RowType(t.row.fields, t.row)
    BoxType(t.name, row, t.handle_map)
end

function resolve(ctx::AnnotateContext, n::SelectNode)
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

gather!(refs::Vector{SQLNode}, n::Union{AsNode, BoxNode, HighlightNode, SortNode}) =
    gather!(refs, n.over)

function gather!(refs::Vector{SQLNode}, n::ExtendedBindNode)
    gather!(refs, n.over)
    gather!(refs, n.list)
    n.owned = true
end

gather!(refs::Vector{SQLNode}, n::FunctionNode) =
    gather!(refs, n.args)

function gather!(refs::Vector{SQLNode}, n::Union{AggregateNode, GetNode, HandleBoundNode, NameBoundNode})
    push!(refs, n)
end

# Validating references.

function validate(ctx::AnnotateContext, t::BoxType, refs::Vector{SQLNode})
    for ref in refs
        validate(ctx, t, ref)
    end
end

function validate(ctx::AnnotateContext, t::BoxType, ref::SQLNode)
    if @dissect ref over |> HandleBound(handle = handle)
        if handle in keys(t.handle_map)
            ht = t.handle_map[handle]
            if ht isa AmbiguousType
                throw(ReferenceError(AMBIGUOUS_HANDLE, path = get_path(ctx, ref)))
            end
            validate(ctx, ht, over)
        else
            throw(ReferenceError(UNDEFINED_HANDLE, path = get_path(ctx, ref)))
        end
    else
        validate(ctx, t.row, ref)
    end
end

function validate(ctx::AnnotateContext, t::RowType, ref::SQLNode)
    while @dissect ref over |> NameBound(name = name)
        ft = get(t.fields, name, EmptyType())
        if !(ft isa RowType)
            type =
                ft isa EmptyType ? UNDEFINED_NAME :
                ft isa ScalarType ? UNEXPECTED_SCALAR_TYPE :
                ft isa AmbiguousType ? AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(ctx, ref)))
        end
        t = ft
        ref = over
    end
    if @dissect ref nothing |> Get(name = name)
        ft = get(t.fields, name, EmptyType())
        if !(ft isa ScalarType)
            type =
                ft isa EmptyType ? UNDEFINED_NAME :
                ft isa RowType ? UNEXPECTED_ROW_TYPE :
                ft isa AmbiguousType ? AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(ctx, ref)))
        end
    elseif @dissect ref nothing |> Agg(name = name)
        if !(t.group isa RowType)
            type =
                t.group isa EmptyType ? UNEXPECTED_AGGREGATE :
                t.group isa AmbiguousType ? AMBIGUOUS_AGGREGATE : error()
            throw(ReferenceError(type, path = get_path(ctx, ref)))
        end
    else
        error()
    end
end

function gather_and_validate!(refs::Vector{SQLNode}, n, ctx::AnnotateContext, t::BoxType)
    start = length(refs) + 1
    gather!(refs, n)
    for k in start:length(refs)
        validate(ctx, t, refs[k])
    end
end

function route(lt::BoxType, rt::BoxType, ref::SQLNode)
    if @dissect ref over |> HandleBound(handle = handle)
        if get(lt.handle_map, ref, EmptyType()) isa RowType
            return -1
        else
            return 1
        end
    end
    return route(lt.row, rt.row, ref)
end

function route(lt::RowType, rt::RowType, ref::SQLNode)
    while @dissect ref over |> NameBound(name = name)
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
    if @dissect ref Get(name = name)
        if name in keys(lt.fields)
            return -1
        else
            return 1
        end
    elseif @dissect ref over |> Agg(name = name)
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
    for box in reverse(ctx.boxes)
        box.over !== nothing || continue
        refs′ = SQLNode[]
        for ref in box.refs
            if (@dissect ref over |> HandleBound(handle = handle)) && handle == box.handle
                push!(refs′, over)
            else
                push!(refs′, ref)
            end
        end
        link!(ctx, box.over[], refs′)
    end
end

function link!(ctx::AnnotateContext, n::AppendNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    for l in n.list
        box = l[]::BoxNode
        append!(box.refs, refs)
    end
end

function link!(ctx::AnnotateContext, n::AsNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    for ref in refs
        if @dissect ref over |> NameBound(name = name)
            @assert name == n.name
            push!(box.refs, over)
        elseif @dissect ref HandleBound()
            push!(box.refs, ref)
        else
            error()
        end
    end
end

function link!(ctx::AnnotateContext, n::DefineNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    seen = Set{Symbol}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            !(name in seen) || continue
            push!(seen, name)
            col = n.list[n.label_map[name]]
            gather_and_validate!(box.refs, col, ctx, box.type)
        else
            push!(box.refs, ref)
        end
    end
end

function link!(ctx::AnnotateContext, n::ExtendedBindNode, refs::Vector{SQLNode})
    if !n.owned
        gather_and_validate!(SQLNode[], n.list, ctx, EMPTY_BOX)
    end
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(ctx::AnnotateContext, n::ExtendedJoinNode, refs::Vector{SQLNode})
    lbox = n.over[]::BoxNode
    rbox = n.joinee[]::BoxNode
    gather_and_validate!(n.lateral, n.joinee, ctx, lbox.type)
    append!(lbox.refs, n.lateral)
    refs′ = SQLNode[]
    gather_and_validate!(refs′, n.on, ctx, n.type)
    append!(refs′, refs)
    for ref in refs′
        turn = route(lbox.type, rbox.type, ref)
        if turn < 0
            push!(lbox.refs, ref)
        else
            push!(rbox.refs, ref)
        end
    end
end

link!(::AnnotateContext, ::FromNode, ::Vector{SQLNode}) =
    nothing

function link!(ctx::AnnotateContext, n::GroupNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    gather_and_validate!(box.refs, n.by, ctx, box.type)
    for ref in refs
        if @dissect ref nothing |> Agg(args = args, filter = filter)
            gather_and_validate!(box.refs, args, ctx, box.type)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, ctx, box.type)
            end
        end
    end
end

function link!(ctx::AnnotateContext, n::Union{HighlightNode, LimitNode}, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(ctx::AnnotateContext, n::OrderNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    gather_and_validate!(box.refs, n.by, ctx, box.type)
end

function link!(ctx::AnnotateContext, n::PartitionNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    for ref in refs
        if @dissect ref nothing |> Agg(args = args, filter = filter)
            gather_and_validate!(box.refs, args, ctx, box.type)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, ctx, box.type)
            end
        else
            push!(box.refs, ref)
        end
    end
    gather_and_validate!(box.refs, n.by, ctx, box.type)
    gather_and_validate!(box.refs, n.order_by, ctx, box.type)
end

function link!(ctx::AnnotateContext, n::SelectNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    gather_and_validate!(box.refs, n.list, ctx, box.type)
end

function link!(ctx::AnnotateContext, n::WhereNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    gather_and_validate!(box.refs, n.condition, ctx, box.type)
end

