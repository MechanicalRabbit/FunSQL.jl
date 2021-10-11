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
    fields = FieldTypeMap(n.name => t.row)
    row = RowType(fields)
    BoxType(n.name, row, t.handle_map)
end

resolve(actx::AnnotateContext, n::Union{BindNode, HighlightNode, LimitNode, OrderNode, WhereNode}) =
    box_type(n.over)

function resolve(actx::AnnotateContext, n::DefineNode)
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

function resolve(actx::AnnotateContext, n::ExtendedJoinNode)
    lt = box_type(n.over)
    rt = box_type(n.joinee)
    t = union(lt, rt)
    n.type = t
    t
end

function resolve(actx::AnnotateContext, n::FromNode)
    fields = FieldTypeMap()
    for f in n.table.columns
        fields[f] = ScalarType()
    end
    row = RowType(fields)
    BoxType(n.table.name, row)
end

function resolve(actx::AnnotateContext, n::GroupNode)
    t = box_type(n.over)
    fields = FieldTypeMap()
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

function gather!(refs::Vector{SQLNode}, n::BindNode)
    gather!(refs, n.over)
    gather!(refs, n.list)
end

gather!(refs::Vector{SQLNode}, n::FunctionNode) =
    gather!(refs, n.args)

function gather!(refs::Vector{SQLNode}, n::Union{AggregateNode, GetNode, HandleBoundNode, NameBoundNode})
    push!(refs, n)
end

# Validating references.

function validate(actx::AnnotateContext, t::BoxType, refs::Vector{SQLNode})
    for ref in refs
        validate(actx, t, ref)
    end
end

function validate(actx::AnnotateContext, t::BoxType, ref::SQLNode)
    if @dissect ref over |> HandleBound(handle = handle)
        if handle in keys(t.handle_map)
            ht = t.handle_map[handle]
            if ht isa AmbiguousType
                throw(ReferenceError(AMBIGUOUS_HANDLE, path = get_path(actx, ref)))
            end
            validate(actx, ht, over)
        else
            throw(ReferenceError(UNDEFINED_HANDLE, path = get_path(actx, ref)))
        end
    else
        validate(actx, t.row, ref)
    end
end

function validate(actx::AnnotateContext, t::RowType, ref::SQLNode)
    while @dissect ref over |> NameBound(name = name)
        ft = get(t.fields, name, EmptyType())
        if !(ft isa RowType)
            type =
                ft isa EmptyType ? UNDEFINED_NAME :
                ft isa ScalarType ? UNEXPECTED_SCALAR_TYPE :
                ft isa AmbiguousType ? AMBIGUOUS_NAME : error()
            throw(ReferenceError(type, name = name, path = get_path(actx, ref)))
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
            throw(ReferenceError(type, name = name, path = get_path(actx, ref)))
        end
    elseif @dissect ref nothing |> Agg(name = name)
        if !(t.group isa RowType)
            type =
                t.group isa EmptyType ? UNEXPECTED_AGGREGATE :
                t.group isa AmbiguousType ? AMBIGUOUS_AGGREGATE : error()
            throw(ReferenceError(type, path = get_path(actx, ref)))
        end
    else
        error()
    end
end

function gather_and_validate!(refs::Vector{SQLNode}, n, actx::AnnotateContext, t::BoxType)
    start = length(refs) + 1
    gather!(refs, n)
    for k in start:length(refs)
        validate(actx, t, refs[k])
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

function link!(actx::AnnotateContext)
    root_box = actx.boxes[end]
    for (f, ft) in root_box.type.row.fields
        if ft isa ScalarType
            push!(root_box.refs, Get(f))
        end
    end
    for box in reverse(actx.boxes)
        box.over !== nothing || continue
        refs′ = SQLNode[]
        for ref in box.refs
            if (@dissect ref over |> HandleBound(handle = handle)) && handle == box.handle
                push!(refs′, over)
            else
                push!(refs′, ref)
            end
        end
        link!(actx, box.over[], refs′)
    end
end

function link!(actx::AnnotateContext, n::AppendNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    for l in n.list
        box = l[]::BoxNode
        append!(box.refs, refs)
    end
end

function link!(actx::AnnotateContext, n::AsNode, refs::Vector{SQLNode})
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

function link!(actx::AnnotateContext, n::Union{BindNode, HighlightNode, LimitNode}, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
end

function link!(actx::AnnotateContext, n::DefineNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    seen = Set{Symbol}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            !(name in seen) || continue
            push!(seen, name)
            col = n.list[n.label_map[name]]
            gather_and_validate!(box.refs, col, actx, box.type)
        else
            push!(box.refs, ref)
        end
    end
end

function link!(actx::AnnotateContext, n::ExtendedJoinNode, refs::Vector{SQLNode})
    lbox = n.over[]::BoxNode
    rbox = n.joinee[]::BoxNode
    gather_and_validate!(n.lateral, n.joinee, actx, lbox.type)
    append!(lbox.refs, n.lateral)
    refs′ = SQLNode[]
    gather_and_validate!(refs′, n.on, actx, n.type)
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

function link!(actx::AnnotateContext, n::GroupNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    gather_and_validate!(box.refs, n.by, actx, box.type)
    for ref in refs
        if @dissect ref nothing |> Agg(args = args, filter = filter)
            gather_and_validate!(box.refs, args, actx, box.type)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, actx, box.type)
            end
        end
    end
end

function link!(actx::AnnotateContext, n::OrderNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    gather_and_validate!(box.refs, n.by, actx, box.type)
end

function link!(actx::AnnotateContext, n::PartitionNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    for ref in refs
        if @dissect ref nothing |> Agg(args = args, filter = filter)
            gather_and_validate!(box.refs, args, actx, box.type)
            if filter !== nothing
                gather_and_validate!(box.refs, filter, actx, box.type)
            end
        else
            push!(box.refs, ref)
        end
    end
    gather_and_validate!(box.refs, n.by, actx, box.type)
    gather_and_validate!(box.refs, n.order_by, actx, box.type)
end

function link!(actx::AnnotateContext, n::SelectNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    gather_and_validate!(box.refs, n.list, actx, box.type)
end

function link!(actx::AnnotateContext, n::WhereNode, refs::Vector{SQLNode})
    box = n.over[]::BoxNode
    append!(box.refs, refs)
    gather_and_validate!(box.refs, n.condition, actx, box.type)
end

