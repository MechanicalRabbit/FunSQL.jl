# Translation to SQL syntax tree.


# Input and output structures for resolution and translation.

mutable struct ResolveContext
    dialect::SQLDialect
    aliases::Dict{Symbol, Int}
    vars::Dict{Symbol, SQLClause}

    ResolveContext(dialect) =
        new(dialect, Dict{Symbol, Int}(), Dict{Symbol, SQLClause}())
end

allocate_alias(ctx::ResolveContext, n) =
    allocate_alias(ctx, label(n))

function allocate_alias(ctx::ResolveContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

struct ResolveRequest
    ctx::ResolveContext
    refs::Vector{SQLNode}
    subs::Dict{SQLNode, SQLClause}

    ResolveRequest(ctx;
                   refs = SQLNode[],
                   subs = Dict{SQLNode, SQLClause}()) =
        new(ctx, refs, subs)
end

struct ResolveResult
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
end

struct TranslateRequest
    ctx::ResolveContext
    subs::Dict{SQLNode, SQLClause}
end

# Substituting references and translating expressions.

function translate(n::SQLNode, treq)
    c = get(treq.subs, n, nothing)
    if c === nothing
        c = convert(SQLClause, translate(n[], treq))
    end
    c
end

translate(ns::Vector{SQLNode}, treq) =
    SQLClause[translate(n, treq) for n in ns]

translate(::Nothing, treq) =
    nothing

translate(n::AggregateNode, treq) =
    translate(Val(n.name), n, treq)

translate(@nospecialize(name::Val{N}), n::AggregateNode, treq) where {N} =
    translate_default(n, treq)

function translate_default(n::AggregateNode, treq)
    args = translate(n.args, treq)
    filter = translate(n.filter, treq)
    AGG(uppercase(string(n.name)), distinct = n.distinct, args = args, filter = filter)
end

function translate(::Val{:count}, n::AggregateNode, treq)
    args = !isempty(n.args) ? translate(n.args, treq) : [OP("*")]
    filter = translate(n.filter, treq)
    AGG(:COUNT, distinct = n.distinct, args = args, filter = filter)
end

translate(n::Union{AsNode, HighlightNode}, treq) =
    translate(n.over, treq)

function translate(n::BindNode, treq)
    vars = treq.ctx.vars
    vars′ = copy(vars)
    for v in n.list
        name = label(v)
        vars′[name] = translate(v, treq)
    end
    treq.ctx.vars = vars′
    c = translate(n.over, treq)
    treq.ctx.vars = vars
    c
end

function translate(n::SubqueryNode, treq)
    req = ResolveRequest(treq.ctx)
    res = resolve(n, req)
    res.clause
end

translate(n::FunctionNode, treq) =
    translate(Val(n.name), n, treq)

translate(@nospecialize(name::Val{N}), n::FunctionNode, treq) where {N} =
    translate_default(n, treq)

function translate_default(n::FunctionNode, treq)
    args = translate(n.args, treq)
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
        translate(::Val{$(QuoteNode(name))}, n::FunctionNode, treq) =
            OP($(QuoteNode(op)),
               args = SQLClause[translate(arg, treq) for arg in n.args])
    end
end

for (name, op, default) in ((:and, :AND, true), (:or, :OR, false))
    @eval begin
        function translate(::Val{$(QuoteNode(name))}, n::FunctionNode, treq)
            args = translate(n.args, treq)
            if isempty(args)
                LIT($default)
            elseif length(args) == 1
                args[1]
            else
                OP($(QuoteNode(op)), args = args)
            end
        end
    end
end

for (name, op, default) in (("in", "IN", false), ("not in", "NOT IN", true))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, treq)
            if length(n.args) <= 1
                LIT($default)
            else
                args = translate(n.args, treq)
                if length(args) == 2 && @dissect args[2] (SELECT() || UNION())
                    OP($op, args = args)
                else
                    OP($op, args[1], FUN("", args = args[2:end]))
                end
            end
        end
    end
end

translate(::Val{Symbol("is null")}, n::FunctionNode, treq) =
    OP(:IS, SQLClause[translate(arg, treq) for arg in n.args]..., missing)

translate(::Val{Symbol("is not null")}, n::FunctionNode, treq) =
    OP(:IS, SQLClause[translate(arg, treq) for arg in n.args]..., OP(:NOT, missing))

translate(::Val{:case}, n::FunctionNode, treq) =
    CASE(args = SQLClause[translate(arg, treq) for arg in n.args])

for (name, op) in (("between", "BETWEEN"), ("not between", "NOT BETWEEN"))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, treq)
            if length(n.args) == 3
                args = SQLClause[translate(arg, treq) for arg in n.args]
                OP($op, args[1], args[2], args[3] |> KW(:AND))
            else
                translate_default(n, treq)
            end
        end
    end
end

for (name, op) in (("current_date", "CURRENT_DATE"),
                   ("current_timestamp", "CURRENT_TIMESTAMP"))
    @eval begin
        function translate(::Val{Symbol($name)}, n::FunctionNode, treq)
            if isempty(n.args)
                OP($op)
            else
                translate_default(n, treq)
            end
        end
    end
end

translate(n::SortNode, treq) =
    SORT(over = translate(n.over, treq), value = n.value, nulls = n.nulls)

translate(n::LiteralNode, treq) =
    LiteralClause(n.val)

function translate(n::VariableNode, treq)
    c = get(treq.ctx.vars, n.name, nothing)
    if c === nothing
        c = VariableClause(n.name)
    end
    c
end

# Resolving deferred SELECT list.

function make_repl(refs::Vector{SQLNode})::Dict{SQLNode, Symbol}
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
        repl[ref] = name
        dups[name′] = 1
    end
    repl
end

function make_repl(trns::Vector{Pair{SQLNode, SQLClause}})::Tuple{Dict{SQLNode, Symbol}, Vector{SQLClause}}
    repl = Dict{SQLNode, Symbol}()
    list = SQLClause[]
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
        push!(list, AS(over = c, name = name′))
        dups[name′] = 1
        renames[name, c] = name′
        repl[ref] = name′
    end
    (repl, list)
end


# Types of SQL nodes.

abstract type AbstractSQLType
end

struct EmptyType <: AbstractSQLType
end

PrettyPrinting.quoteof(::EmptyType, ::SQLNodeQuoteContext) =
    Expr(:call, nameof(EmptyType))

struct RowType <: AbstractSQLType
    fields::OrderedDict{Symbol, AbstractSQLType}
    group::AbstractSQLType

    RowType(fields, group = EmptyType()) =
        new(fields, group)
end

RowType() =
    RowType(OrderedDict{Symbol, AbstractSQLType}())

function PrettyPrinting.quoteof(t::RowType, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(RowType))
    if qctx.limit
        push!(ex.args, :…)
    else
        push!(ex.args, quoteof(t.fields))
        if !(t.group isa EmptyType)
            push!(ex.args, quoteof(t.group, qctx))
        end
    end
    ex
end

function PrettyPrinting.quoteof(d::Dict{Symbol, AbstractSQLType}, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Dict))
    for (k, v) in d
        push!(ex.args, Expr(:call, :(=>), QuoteNode(k), quoteof(v, qctx)))
    end
    ex
end

struct ScalarType <: AbstractSQLType
end

PrettyPrinting.quoteof(::ScalarType, ::SQLNodeQuoteContext) =
    Expr(:call, nameof(ScalarType))

struct AmbiguousType <: AbstractSQLType
end

PrettyPrinting.quoteof(::AmbiguousType, ::SQLNodeQuoteContext) =
    Expr(:call, nameof(AmbiguousType))

Base.intersect(::AbstractSQLType, ::AbstractSQLType) =
    EmptyType()

Base.intersect(::ScalarType, ::ScalarType) =
    ScalarType()

Base.intersect(::AmbiguousType, ::AmbiguousType) =
    AmbiguousType()

function Base.intersect(t1::RowType, t2::RowType)
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for f in keys(t1.fields)
        if f in keys(t2.fields)
            t = intersect(t1.fields[f], t2.fields[f])
            if !isa(t, EmptyType)
                fields[f] = t
            end
        end
    end
    group = intersect(t1.group, t2.group)
    RowType(fields, group)
end

Base.union(::AbstractSQLType, ::AbstractSQLType) =
    AmbiguousType()

Base.union(::EmptyType, ::EmptyType) =
    EmptyType()

Base.union(::EmptyType, t::AbstractSQLType) =
    t

Base.union(t::AbstractSQLType, ::EmptyType) =
    t

Base.union(::ScalarType, ::ScalarType) =
    ScalarType()

function Base.union(t1::RowType, t2::RowType)
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for (f, t) in t1.fields
        if f in keys(t2.fields)
            t′ = t2.fields[f]
            if t isa RowType && t′ isa RowType
                t = union(t, t′)
            else
                t = AmbiguousType()
            end
        end
        fields[f] = t
    end
    for (f, t) in t2.fields
        if !(f in keys(t1.fields))
            fields[f] = t
        end
    end
    if t1.group isa EmptyType
        group = t2.group
    elseif t2.group isa EmptyType
        group = t1.group
    else
        group = AmbiguousType()
    end
    RowType(fields, group)
end


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

mutable struct NodeBoundNode <: AbstractSQLNode
    over::SQLNode
    node::SQLNode

    NodeBoundNode(; over, node) =
        new(over, node)
end

NodeBound(args...; kws...) =
    NodeBoundNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(NodeBound), pats::Vector{Any}) =
    dissect(scr, NodeBoundNode, pats)

mutable struct TerminalNode <: AbstractSQLNode
end

Terminal() = TerminalNode() |> SQLNode

mutable struct ExportNode <: AbstractSQLNode
    over::SQLNode
    name::Symbol
    type::RowType
    node_map::Dict{SQLNode, RowType} # Set{SQLNode}
    origin::SQLNode
    refs::Vector{SQLNode}
    lateral_refs::Vector{SQLNode}

    ExportNode(;
               over,
               name::Symbol,
               type::RowType,
               node_map::Dict{SQLNode, RowType},
               origin,
               refs::Vector{SQLNode} = SQLNode[],
               lateral_refs::Vector{SQLNode} = SQLNode[]) =
        new(over, name, type, node_map, origin, refs, lateral_refs)
end

Export(args...; kws...) =
    ExportNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::ExportNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Export))
    push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
    push!(ex.args, Expr(:kw, :type, quoteof(n.type, qctx)))
    if !isempty(n.refs)
        push!(ex.args, Expr(:kw, :refs, Expr(:vect, quoteof(n.refs, qctx)...)))
    end
    ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    ex
end

label(n::ExportNode) =
    n.name

label(n::Union{NameBoundNode, NodeBoundNode}) =
    label(n.over)

get_export(n::SQLNode) =
    get_export(n[])

get_export(n::ExportNode) =
    n

get_export(::AbstractSQLNode) =
    error()


# Building a SQL query out of a SQL node tree.

asterix(n::SQLNode) =
    asterix(get_export(n).type)

function asterix(t::RowType)
    list = SQLNode[]
    for (f, ft) in t.fields
        !(ft isa RowType) || continue
        push!(list, Get(f))
    end
    list
end

function render(n; dialect = :default)
    actx = AnnotateContext()
    n′ = annotate(actx, convert(SQLNode, n))
    ctx = ResolveContext(dialect)
    req = ResolveRequest(ctx, refs = asterix(n′))
    populate!(actx, n′, req)
    res = build(n′, ctx)
    c = collapse(res.clause)
    sql = render(c, dialect = dialect)
    sql
end


# Annotating SQL nodes.

struct AnnotateContext
    paths::Vector{Tuple{SQLNode, Int}}
    origins::Dict{SQLNode, Int}
    stack::Vector{Int}

    AnnotateContext() =
        new(Tuple{SQLNode, Int}[], Dict{SQLNode, Int}(), Int[0])
end

struct ValidateContext
    paths::Vector{Tuple{SQLNode, Int}}
    origins::Dict{SQLNode, Int}
    type::RowType
    node_map::Dict{SQLNode, RowType}

    ValidateContext(actx::AnnotateContext, exp::ExportNode) =
        new(actx.paths, actx.origins, exp.type, exp.node_map)
end

function get_stack(vctx::ValidateContext, n::SQLNode)
    stack = SQLNode[]
    idx = get(vctx.origins, n, 0)
    while idx != 0
        n, idx = vctx.paths[idx]
        push!(stack, n)
    end
    stack
end

function validate(vctx::ValidateContext, ref::SQLNode, t::RowType)
    while @dissect ref over |> NameBound(name = name)
        if !(name in keys(t.fields))
            throw(GetError(name, stack = get_stack(vctx, ref)))
        end
        t′ = t.fields[name]
        if t′ isa AmbiguousType
            throw(GetError(name, ambiguous = true, stack = get_stack(vctx, ref)))
        end
        if t′ isa RowType
            t = t′
        else
            error()
        end
        ref = over
    end
    if @dissect ref Get(name = name)
        if !(name in keys(t.fields))
            throw(GetError(name, stack = get_stack(vctx, ref)))
        end
        t′ = t.fields[name]
        if t′ isa AmbiguousType
            throw(GetError(name, ambiguous = true, stack = get_stack(vctx, ref)))
        end
        if !(t′ isa ScalarType)
            error()
        end
    elseif @dissect ref over |> Agg(name = name)
        if !(t.group isa RowType)
            error()
        end
    else
        error()
    end
    nothing
end

function validate(vctx::ValidateContext, ref::SQLNode)
    if @dissect ref over |> NodeBound(node = node)
        if haskey(vctx.node_map, node)
            t = vctx.node_map[node]
            validate(vctx, over, t)
        else
            error()
        end
    else
        validate(vctx, ref, vctx.type)
    end
end

function route(lt::RowType, rt::RowType, ref::SQLNode)
    while @dissect ref over |> NameBound(name = name)
        if name in keys(lt.fields)
            if name in keys(rt.fields)
                lt′ = lt.fields[name]
                rt′ = rt.fields[name]
                if lt′ isa RowType && rt′ isa RowType
                    lt = lt′
                    rt = rt′
                    ref = over
                else
                    error()
                end
            else
                return -1
            end
        else
            return 1
        end
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

function route(lvctx::ValidateContext, rvctx::ValidateContext, ref::SQLNode)
    if @dissect ref over |> NodeBound(node = node)
        lturn = haskey(lvctx.node_map, node)
        rturn = haskey(rvctx.node_map, node)
        @assert lturn != rturn
        return lturn ? -1 : 1
    else
        return route(lvctx.type, rvctx.type, ref)
    end
end

function gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::SQLNode)
    gather!(vctx, refs, n[])
    refs
end

function gather!(vctx::ValidateContext, refs::Vector{SQLNode}, ns::Vector{SQLNode})
    for n in ns
        gather!(vctx, refs, n)
    end
    refs
end

gather!(vctx::ValidateContext, refs::Vector{SQLNode}, ::AbstractSQLNode) =
    refs

function gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::Union{AggregateNode, GetNode})
    validate(vctx, convert(SQLNode, n))
    push!(refs, n)
end

gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::Union{AsNode, HighlightNode, SortNode}) =
    gather!(vctx, refs, n.over)

function gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::BindNode)
    gather!(vctx, refs, n.over)
    gather!(vctx, refs, n.list)
end

gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::FunctionNode) =
    gather!(vctx, refs, n.args)

gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::ExportNode) =
    gather!(vctx, refs, n.over)

function gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::Union{NameBoundNode, NodeBoundNode})
    validate(vctx, convert(SQLNode, n))
    push!(refs, n)
end

function annotate(actx::AnnotateContext, n::SQLNode)
    push!(actx.paths, (n, actx.stack[end]))
    idx = length(actx.paths)
    push!(actx.stack, idx)
    n′ = convert(SQLNode, annotate(actx, n[]))
    actx.origins[n′] = idx
    pop!(actx.stack)
    n′
end

function annotate_scalar(actx::AnnotateContext, n::SQLNode)
    push!(actx.paths, (n, actx.stack[end]))
    idx = length(actx.paths)
    push!(actx.stack, idx)
    n′ = convert(SQLNode, annotate_scalar(actx, n[]))
    actx.origins[n′] = idx
    pop!(actx.stack)
    n′
end

annotate(actx::AnnotateContext, ns::Vector{SQLNode}) =
    SQLNode[annotate(actx, n) for n in ns]

annotate_scalar(actx::AnnotateContext, ns::Vector{SQLNode}) =
    SQLNode[annotate_scalar(actx, n) for n in ns]

annotate_scalar(actx::AnnotateContext, n::SubqueryNode) =
    annotate(actx, n)

function annotate(actx::AnnotateContext, ::Nothing)
    n = Terminal()
    actx.origins[n] = actx.stack[end]
    exp = ExportNode(over = n, name = :_, type = RowType(), node_map = Dict{SQLNode, RowType}(), origin = n)
    actx.origins[convert(SQLNode, exp)] = actx.stack[end]
    exp
end

bind(actx::AnnotateContext, ::Nothing, base) =
    base

function bind(actx::AnnotateContext, node, base)
    actx.origins[base] = actx.stack[end]
    if @dissect node over |> Get(name = name)
        bind(actx, over, NameBound(over = base, name = name))
    else
        return NodeBound(over = base, node = node)
    end
end

function annotate_scalar(actx::AnnotateContext, n::GetNode)
    bind(actx, n.over, Get(name = n.name))
end

function annotate_scalar(actx::AnnotateContext, n::FunctionNode)
    args′ = annotate_scalar(actx, n.args)
    FunctionNode(name = n.name, args = args′)
end

function annotate_scalar(actx::AnnotateContext, n::AggregateNode)
    args′ = annotate_scalar(actx, n.args)
    filter′ = annotate_scalar(actx, n.filter)
    n′ = AggregateNode(name = n.name, distinct = n.distinct, args = args′, filter = filter′)
    bind(actx, n.over, convert(SQLNode, n′))
end

function annotate_scalar(actx::AnnotateContext, n::SortNode)
    over′ = annotate_scalar(actx, n.over)
    SortNode(over = over′, value = n.value, nulls = n.nulls)
end

function annotate_scalar(actx::AnnotateContext, n::HighlightNode)
    over′ = annotate_scalar(actx, n.over)
    HighlightNode(over = over′, color = n.color)
end

function annotate(actx::AnnotateContext, n::HighlightNode)
    over′ = annotate(actx, n.over)
    n′ = Highlight(over = over′, color = n.color)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = exp.name, type = exp.type, node_map = node_map, origin = n)
end

annotate_scalar(actx::AnnotateContext, n::Union{Nothing, LiteralNode, VariableNode}) =
    n

function annotate(actx::AnnotateContext, n::AppendNode)
    over′ = annotate(actx, n.over)
    list′ = annotate(actx, n.list)
    n′ = Append(over = over′, list = list′)
    actx.origins[n′] = actx.stack[end]
    lexp = get_export(over′)
    t = lexp.type
    node_map = lexp.node_map
    for r in list′
        rexp = get_export(r)
        t = intersect(t, rexp.type)
        node_map′ = Dict{SQLNode, RowType}()
        for (k, kt) in node_map
            if haskey(rexp.node_map, k)
                node_map′[k] = intersect(kt, rexp.node_map[k])
            end
        end
        node_map = node_map′
    end
    node_map[convert(SQLNode, n)] = t
    ExportNode(over = n′, name = :union, type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::AsNode)
    over′ = annotate(actx, n.over)
    n′ = As(over = over′, name = n.name)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    t = exp.type
    fields = OrderedDict{Symbol, AbstractSQLType}(n.name => t)
    t′ = RowType(fields)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = t
    ExportNode(over = n′, name = n.name, type = t′, node_map = node_map, origin = n)
end

function annotate_scalar(actx::AnnotateContext, n::AsNode)
    over′ = annotate_scalar(actx, n.over)
    AsNode(over = over′, name = n.name)
end

annotate_scalar(actx::AnnotateContext, n::BindNode) =
    annotate(actx, n)

function annotate(actx::AnnotateContext, n::BindNode)
    over′ = annotate(actx, n.over)
    list′ = annotate_scalar(actx, n.list)
    n′ = Bind(over = over′, list = list′)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = label(n), type = exp.type, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::DefineNode)
    over′ = annotate(actx, n.over)
    list′ = annotate_scalar(actx, n.list)
    n′ = Define(over = over′, list = list′, label_map = n.label_map)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for (f, t) in exp.type.fields
        if f in keys(n.label_map)
            t = ScalarType()
        end
        fields[f] = t
    end
    for f in keys(n.label_map)
        if !haskey(fields, f)
            fields[f] = ScalarType()
        end
    end
    t = RowType(fields)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = label(n), type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::FromNode)
    actx.origins[convert(SQLNode, n)] = actx.stack[end]
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for f in n.table.columns
        fields[f] = ScalarType()
    end
    t = RowType(fields)
    node_map = Dict{SQLNode, RowType}(convert(SQLNode, n) => t)
    ExportNode(over = n, name = n.table.name, type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::GroupNode)
    over′ = annotate(actx, n.over)
    by′ = annotate_scalar(actx, n.by)
    n′ = Group(over = over′, by = by′, label_map = n.label_map)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    fields = Dict{Symbol, AbstractSQLType}()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    t = RowType(fields, exp.type)
    node_map = Dict{SQLNode, RowType}(convert(SQLNode, n) => t)
    ExportNode(over = n′, name = exp.name, type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::JoinNode)
    over′ = annotate(actx, n.over)
    joinee′ = annotate(actx, n.joinee)
    on′ = annotate_scalar(actx, n.on)
    n′ = Join(over = over′, joinee = joinee′, on = on′, left = n.left, right = n.right)
    actx.origins[n′] = actx.stack[end]
    lexp = get_export(over′)
    rexp = get_export(joinee′)
    t = union(lexp.type, rexp.type)
    node_map = Dict{SQLNode, RowType}()
    for l in keys(lexp.node_map)
        if haskey(rexp.node_map, l)
            node_map[l] = AmbiguousType()
        else
            node_map[l] = lexp.node_map[l]
        end
    end
    for l in keys(rexp.node_map)
        if !haskey(lexp.node_map, l)
            node_map[l] = rexp.node_map[l]
        end
    end
    node_map[convert(SQLNode, n)] = t
    ExportNode(over = n′, name = lexp.name, type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::LimitNode)
    over′ = annotate(actx, n.over)
    n′ = Limit(over = over′, offset = n.offset, limit = n.limit)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = label(n), type = exp.type, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::OrderNode)
    over′ = annotate(actx, n.over)
    by′ = annotate_scalar(actx, n.by)
    n′ = Order(over = over′, by = by′)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = label(n), type = exp.type, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::PartitionNode)
    over′ = annotate(actx, n.over)
    by′ = annotate_scalar(actx, n.by)
    order_by′ = annotate_scalar(actx, n.order_by)
    n′ = Partition(over = over′, by = by′, order_by = order_by′, frame = n.frame)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    t = RowType(exp.type.fields, exp.type)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = label(n), type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::SelectNode)
    over′ = annotate(actx, n.over)
    list′ = annotate_scalar(actx, n.list)
    n′ = Select(over = over′, list = list′, label_map = n.label_map)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    fields = OrderedDict{Symbol, AbstractSQLType}()
    for name in keys(n.label_map)
        fields[name] = ScalarType()
    end
    t = RowType(fields)
    node_map = Dict{SQLNode, RowType}(convert(SQLNode, n) => t)
    ExportNode(over = n′, name = exp.name, type = t, node_map = node_map, origin = n)
end

function annotate(actx::AnnotateContext, n::WhereNode)
    over′ = annotate(actx, n.over)
    condition′ = annotate_scalar(actx, n.condition)
    n′ = Where(over = over′, condition = condition′)
    actx.origins[n′] = actx.stack[end]
    exp = get_export(over′)
    node_map = copy(exp.node_map)
    node_map[convert(SQLNode, n)] = exp.type
    ExportNode(over = n′, name = label(n), type = exp.type, node_map = node_map, origin = n)
end


# Populating export list of SQL subqueries.

populate!(actx::AnnotateContext, n::SQLNode, req::ResolveRequest) =
    populate!(actx, n[], req)

populate!(actx::AnnotateContext, exp::ExportNode, n::SQLNode, req::ResolveRequest) =
    populate!(actx, exp, n[], req)

function populate!(actx::AnnotateContext, ns::Vector{SQLNode}, req::ResolveRequest)
    for n in ns
        populate!(actx, n, req)
    end
end

function populate!(actx::AnnotateContext, ::Nothing, req::ResolveRequest)
    nothing
end

populate!(actx::AnnotateContext, n::Union{AsNode, HighlightNode, NameBoundNode, NodeBoundNode, SortNode}, req::ResolveRequest) =
    populate!(actx, n.over, req)

populate!(::AnnotateContext, ::Union{GetNode, LiteralNode, TerminalNode, VariableNode}, ::ResolveRequest) =
    nothing

populate!(actx::AnnotateContext, n::FunctionNode, req::ResolveRequest) =
    populate!(actx, n.args, req)

function populate!(actx::AnnotateContext, n::AggregateNode, req::ResolveRequest)
    populate!(actx, n.args, req)
    populate!(actx, n.filter, req)
end

function populate!(actx::AnnotateContext, n::ExportNode, req::ResolveRequest)
    append!(n.refs, req.refs)
    refs′ = SQLNode[]
    for ref in req.refs
        if (@dissect ref over |> NodeBoundNode(node = node)) && node === n.origin
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    populate!(actx, n, n.over, ResolveRequest(req.ctx, refs = refs′))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::AppendNode, req::ResolveRequest)
    populate!(actx, n.over, req)
    for l in n.list
        populate!(actx, l, req)
    end
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::AsNode, req::ResolveRequest)
    refs′ = SQLNode[]
    for ref in req.refs
        if @dissect ref over |> NameBound(name = name)
            @assert name == n.name
            push!(refs′, over)
        elseif @dissect ref NodeBound()
            push!(refs′, ref)
        else
            error()
        end
    end
    populate!(actx, n.over, ResolveRequest(req.ctx, refs = refs′))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::BindNode, req::ResolveRequest)
    base_req = ResolveRequest(req.ctx, refs = req.refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.list, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::DefineNode, req::ResolveRequest)
    vctx = ValidateContext(actx, get_export(n.over))
    base_refs = SQLNode[]
    seen = Set{Symbol}()
    for ref in req.refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            !(name in seen) || continue
            push!(seen, name)
            col = n.list[n.label_map[name]]
            gather!(vctx, base_refs, col)
        else
            push!(base_refs, ref)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.list, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::GroupNode, req::ResolveRequest)
    vctx = ValidateContext(actx, get_export(n.over))
    base_refs = SQLNode[]
    gather!(vctx, base_refs, n.by)
    for ref in req.refs
        if @dissect ref (nothing |> Agg(args = args, filter = filter))
            gather!(vctx, base_refs, args)
            if filter !== nothing
                gather!(vctx, base_refs, filter)
            end
            has_aggregates = true
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.by, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::HighlightNode, req::ResolveRequest)
    populate!(actx, n.over, req)
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::JoinNode, req::ResolveRequest)
    vctx = ValidateContext(actx, exp)
    lexp = get_export(n.over)
    rexp = get_export(n.joinee)
    refs = SQLNode[]
    gather!(vctx, refs, n.on)
    append!(refs, req.refs)
    lrefs = SQLNode[]
    rrefs = SQLNode[]
    lvctx = ValidateContext(actx, lexp)
    rvctx = ValidateContext(actx, rexp)
    for ref in refs
        turn = route(lvctx, rvctx, ref)
        if turn < 0
            push!(lrefs, ref)
        else
            push!(rrefs, ref)
        end
    end
    gather!(lvctx, exp.lateral_refs, n.joinee)
    append!(lrefs, exp.lateral_refs)
    populate!(actx, n.over, ResolveRequest(req.ctx, refs = lrefs))
    populate!(actx, n.joinee, ResolveRequest(req.ctx, refs = rrefs))
    populate!(actx, n.on, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::LimitNode, req::ResolveRequest)
    populate!(actx, n.over, req)
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::OrderNode, req::ResolveRequest)
    vctx = ValidateContext(actx, get_export(n.over))
    base_refs = copy(req.refs)
    gather!(vctx, base_refs, n.by)
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.by, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::PartitionNode, req::ResolveRequest)
    vctx = ValidateContext(actx, get_export(n.over))
    base_refs = SQLNode[]
    gather!(vctx, base_refs, n.by)
    gather!(vctx, base_refs, n.order_by)
    for ref in req.refs
        if @dissect ref (nothing |> Agg(args = args, filter = filter))
            gather!(vctx, base_refs, args)
            if filter !== nothing
                gather!(vctx, base_refs, filter)
            end
        else
            push!(base_refs, ref)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.by, ResolveRequest(req.ctx))
    populate!(actx, n.order_by, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::SelectNode, req::ResolveRequest)
    vctx = ValidateContext(actx, get_export(n.over))
    base_refs = SQLNode[]
    gather!(vctx, base_refs, n.list)
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.list, ResolveRequest(req.ctx))
end

function populate!(actx::AnnotateContext, exp::ExportNode, n::WhereNode, req::ResolveRequest)
    vctx = ValidateContext(actx, get_export(n.over))
    base_refs = copy(req.refs)
    gather!(vctx, base_refs, n.condition)
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.condition, ResolveRequest(req.ctx))
end

populate!(actx::AnnotateContext, ::ExportNode, ::Union{FromNode, TerminalNode}, ::ResolveRequest) =
    nothing


# Building SQL clauses.

build(n::SQLNode, ctx::ResolveContext) =
    build(n[], ctx)

build(n::SQLNode, treq::TranslateRequest) =
    build(n[], treq)

function build(::Nothing, ctx::ResolveContext)
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    ResolveResult(c, repl)
end

build(n::AbstractSQLNode, ctx::Union{ResolveContext, TranslateRequest}, refs::Vector{SQLNode}, lateral_refs::Vector{SQLNode}) =
    build(n, ctx, refs)

build(n::SQLNode, ctx::Union{ResolveContext, TranslateRequest}, refs::Vector{SQLNode}, lateral_refs::Vector{SQLNode}) =
    build(n[], ctx, refs, lateral_refs)

build(n::SubqueryNode, treq::TranslateRequest, refs::Vector{SQLNode}) =
    build(n, treq.ctx, refs)

translate(n::ExportNode, treq::TranslateRequest) =
    build(n, treq).clause

function build(n::ExportNode, ctx::ResolveContext)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> NodeBoundNode(node = node)) && node === n.origin
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = build(n.over, ctx, refs′, n.lateral_refs)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> NodeBoundNode(node = node)) && node === n.origin
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    ResolveResult(res.clause, repl′)
end

function build(n::ExportNode, treq::TranslateRequest)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> NodeBoundNode(node = node)) && node === n.origin
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = build(n.over, treq, refs′, n.lateral_refs)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> NodeBoundNode(node = node)) && node === n.origin
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    ResolveResult(res.clause, repl′)
end

function build(n::TerminalNode, ctx::ResolveContext, refs::Vector{SQLNode})
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    ResolveResult(c, repl)
end

function build(n::AppendNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    as = allocate_alias(ctx, n.over)
    results = [as => base_res]
    for l in n.list
        res = build(l, ctx)
        as = allocate_alias(ctx, l)
        push!(results, as => res)
    end
    dups = Dict{SQLNode, SQLNode}()
    seen = Dict{Symbol, SQLNode}()
    for ref in refs
        name = base_res.repl[ref]
        if name in keys(seen)
            other_ref = seen[name]
            if all(res.repl[ref] === res.repl[other_ref] for (as, res) in results)
                dups[ref] = seen[name]
            end
        else
            seen[name] = ref
        end
    end
    urefs = SQLNode[ref for ref in refs if !(ref in keys(dups))]
    repl = make_repl(urefs)
    for (ref, uref) in dups
        repl[ref] = repl[uref]
    end
    cs = SQLClause[]
    for (as, res) in results
        list = SQLClause[]
        for ref in refs
            !(ref in keys(dups)) || continue
            name = repl[ref]
            id = ID(over = as, name = res.repl[ref])
            push!(list, AS(over = id, name = name))
        end
        if isempty(list)
            push!(list, missing)
        end
        c = SELECT(over = FROM(AS(over = res.clause, name = as)),
                   list = list)
        push!(cs, c)
    end
    c = UNION(over = cs[1], all = true, list = cs[2:end])
    ResolveResult(c, repl)
end

function build(n::AsNode, ctx::Union{ResolveContext, TranslateRequest}, refs::Vector{SQLNode})
    res = build(n.over, ctx)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect ref over |> NameBound()
            @assert over !== nothing
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    ResolveResult(res.clause, repl′)
end

function build(n::BindNode, treq::TranslateRequest, refs::Vector{SQLNode})
    ctx = treq.ctx
    vars = ctx.vars
    vars′ = copy(vars)
    for v in n.list
        name = label(v)
        vars′[name] = translate(v, treq)
    end
    ctx.vars = vars′
    res = build(n.over, ctx)
    ctx.vars = vars
    res
end

build(n::BindNode, ctx::ResolveContext, refs::Vector{SQLNode}) =
    build(n, TranslateRequest(ctx, Dict{SQLNode, SQLClause}()), refs)

function build(n::DefineNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    repl = Dict{SQLNode, Symbol}()
    trns = Pair{SQLNode, SQLClause}[]
    tr_cache = Dict{Symbol, SQLClause}()
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if (@dissect ref (nothing |> Get(name = name))) && name in keys(n.label_map)
            c = get!(tr_cache, name) do
                col = n.list[n.label_map[name]]
                translate(col, treq)
            end
            push!(trns, ref => c)
        elseif ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get!(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    c = SELECT(over = f, list = list)
    ResolveResult(c, repl)
end

function build(n::FromNode, ctx::ResolveContext, refs::Vector{SQLNode})
    output_columns = Set{Symbol}()
    for ref in refs
        match = @dissect ref (nothing |> Get(name = name))
        @assert match && name in n.table.column_set
        if !(name in output_columns)
            push!(output_columns, name)
        end
    end
    as = allocate_alias(ctx, n.table.name)
    list = SQLClause[AS(over = ID(over = as, name = col), name = col)
                     for col in n.table.columns
                     if col in output_columns]
    if isempty(list)
        push!(list, missing)
    end
    tbl = ID(over = n.table.schema, name = n.table.name)
    c = SELECT(over = FROM(AS(over = tbl, name = as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        if @dissect ref (nothing |> Get(name = name))
            repl[ref] = name
        end
    end
    ResolveResult(c, repl)
end

function build(n::GroupNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    by = SQLClause[]
    tr_cache = Dict{Symbol, SQLClause}()
    for (i, name) in enumerate(keys(n.label_map))
        key = n.by[i]
        ckey = translate(key, treq)
        push!(by, ckey)
        tr_cache[name] = ckey
    end
    has_keys = !isempty(by)
    has_aggregates = false
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if @dissect ref (nothing |> Get(name = name))
            @assert name in keys(n.label_map)
            ckey = tr_cache[name]
            push!(trns, ref => ckey)
        elseif @dissect ref (nothing |> Agg(name = name))
            c = translate(ref, treq)
            push!(trns, ref => c)
            has_aggregates = true
        end
    end
    if !has_keys && !has_aggregates
        return build(nothing, ctx)
    end
    repl, list = make_repl(trns)
    @assert !isempty(list)
    f = FROM(AS(over = base_res.clause, name = base_as))
    if has_aggregates
        g = GROUP(over = f, by = by)
        c = SELECT(over = g, list = list)
    else
        c = SELECT(over = f, distinct = true, list = list)
    end
    ResolveResult(c, repl)
end

build(n::HighlightNode, ctx::ResolveContext, refs::Vector{SQLNode}) =
    build(n.over, ctx)

function build(n::JoinNode, ctx::ResolveContext, refs::Vector{SQLNode}, lateral_refs::Vector{SQLNode})
    left_res = build(n.over, ctx)
    left_as = allocate_alias(ctx, n.over)
    lateral = !isempty(lateral_refs)
    if lateral
        lsubs = Dict{SQLNode, SQLClause}()
        for ref in lateral_refs
            name = left_res.repl[ref]
            lsubs[ref] = ID(over = left_as, name = name)
        end
        treq = TranslateRequest(ctx, lsubs)
        right_res = build(n.joinee, treq)
    else
        right_res = build(n.joinee, ctx)
    end
    right_as = allocate_alias(ctx, n.joinee)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in left_res.repl
        subs[ref] = ID(over = left_as, name = name)
    end
    for (ref, name) in right_res.repl
        subs[ref] = ID(over = right_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    on = translate(n.on, treq)
    l_cache = Dict{Symbol, SQLClause}()
    r_cache = Dict{Symbol, SQLClause}()
    trns = Pair{SQLNode, SQLClause}[]
    for ref in refs
        if ref in keys(left_res.repl)
            name = left_res.repl[ref]
            c = get!(l_cache, name) do
                ID(over = left_as, name = name)
            end
            push!(trns, ref => c)
        elseif ref in keys(right_res.repl)
            name = right_res.repl[ref]
            c = get!(r_cache, name) do
                ID(over = right_as, name = name)
            end
            push!(trns, ref => c)
        else
            error()
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    j = JOIN(over = FROM(AS(over = left_res.clause, name = left_as)),
             joinee = AS(over = right_res.clause, name = right_as),
             on = on,
             left = n.left,
             right = n.right,
             lateral = lateral)
    c = SELECT(over = j, list = list)
    ResolveResult(c, repl)
end

function build(n::LimitNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        name = base_res.repl[ref]
        c = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
        push!(trns, ref => c)
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    if n.offset !== nothing || n.limit !== nothing
        l = LIMIT(over = f, offset = n.offset, limit = n.limit)
    else
        l = f
    end
    c = SELECT(over = l, list = list)
    ResolveResult(c, repl)
end

function build(n::OrderNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    by = translate(n.by, treq)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        name = base_res.repl[ref]
        c = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
        push!(trns, ref => c)
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    f = FROM(AS(over = base_res.clause, name = base_as))
    if !isempty(by)
        o = ORDER(over = f, by = by)
    else
        o = f
    end
    c = SELECT(over = o, list = list)
    ResolveResult(c, repl)
end

function build(n::PartitionNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    by = translate(n.by, treq)
    order_by = translate(n.order_by, treq)
    partition = PARTITION(by = by, order_by = order_by, frame = n.frame)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        if @dissect ref (nothing |> Agg(name = name))
            c = partition |> translate(ref, treq)
            push!(trns, ref => c)
        else
            @assert ref in keys(base_res.repl)
            name = base_res.repl[ref]
            c = get!(base_cache, name) do
                ID(over = base_as, name = name)
            end
            push!(trns, ref => c)
        end
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    w = WINDOW(over = FROM(AS(over = base_res.clause, name = base_as)), list = [])
    c = SELECT(over = w, list = list)
    ResolveResult(c, repl)
end

function build(n::SelectNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    list = SQLClause[]
    treq = TranslateRequest(ctx, subs)
    for (i, name) in enumerate(keys(n.label_map))
        col = n.list[i]
        c = translate(col, treq)
        c = AS(over = c, name = name)
        push!(list, c)
    end
    if isempty(list)
        push!(list, missing)
    end
    c = SELECT(over = FROM(AS(over = base_res.clause, name = base_as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in refs
        ref_name = nothing
        @dissect ref (nothing |> Get(name = name))
        @assert name !== nothing
        repl[ref] = name
    end
    ResolveResult(c, repl)
end

function build(n::WhereNode, ctx::ResolveContext, refs::Vector{SQLNode})
    base_res = build(n.over, ctx)
    base_as = allocate_alias(ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    treq = TranslateRequest(ctx, subs)
    condition = translate(n.condition, treq)
    trns = Pair{SQLNode, SQLClause}[]
    base_cache = Dict{Symbol, SQLClause}()
    for ref in refs
        @assert ref in keys(base_res.repl)
        name = base_res.repl[ref]
        c = get(base_cache, name) do
            ID(over = base_as, name = name)
        end
        push!(trns, ref => c)
    end
    repl, list = make_repl(trns)
    if isempty(list)
        push!(list, missing)
    end
    w = WHERE(over = FROM(AS(over = base_res.clause, name = base_as)),
              condition = condition)
    c = SELECT(over = w, list = list)
    ResolveResult(c, repl)
end

