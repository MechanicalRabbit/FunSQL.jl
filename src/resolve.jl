# Translation to SQL syntax tree.


# Input and output structures for resolution and translation.

mutable struct BuildContext
    dialect::SQLDialect
    aliases::Dict{Symbol, Int}
    vars::Dict{Symbol, SQLClause}

    BuildContext(dialect) =
        new(dialect, Dict{Symbol, Int}(), Dict{Symbol, SQLClause}())
end

allocate_alias(ctx::BuildContext, n) =
    allocate_alias(ctx, label(n))

function allocate_alias(ctx::BuildContext, alias::Symbol)
    n = get(ctx.aliases, alias, 0) + 1
    ctx.aliases[alias] = n
    Symbol(alias, '_', n)
end

struct BuildRequest
    ctx::BuildContext
    refs::Vector{SQLNode}
    subs::Dict{SQLNode, SQLClause}

    BuildRequest(ctx;
                   refs = SQLNode[],
                   subs = Dict{SQLNode, SQLClause}()) =
        new(ctx, refs, subs)
end

struct BuildResult
    clause::SQLClause
    repl::Dict{SQLNode, Symbol}
end

struct TranslateRequest
    ctx::BuildContext
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


# Building a SQL query out of a SQL node tree.

asterix(n::SQLNode) =
    asterix(box_type(n))

asterix(t::BoxType) =
    asterix(t.row)

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
    resolve!(actx)
    ctx = BuildContext(dialect)
    req = BuildRequest(ctx, refs = asterix(n′))
    populate!(actx, n′, req)
    res = build(n′, ctx)
    c = collapse(res.clause)
    sql = render(c, dialect = dialect)
    sql
end

struct ValidateContext
    paths::Vector{Tuple{SQLNode, Int}}
    origins::Dict{SQLNode, Int}
    type::BoxType

    ValidateContext(actx::AnnotateContext, type::BoxType) =
        new(actx.paths, actx.origins, type)
end

function get_path(vctx::ValidateContext, n::SQLNode)
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
            throw(GetError(name, path = get_path(vctx, ref)))
        end
        t′ = t.fields[name]
        if t′ isa AmbiguousType
            throw(GetError(name, ambiguous = true, path = get_path(vctx, ref)))
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
            throw(GetError(name, path = get_path(vctx, ref)))
        end
        t′ = t.fields[name]
        if t′ isa AmbiguousType
            throw(GetError(name, ambiguous = true, path = get_path(vctx, ref)))
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

function validate(vctx::ValidateContext, ref::SQLNode, t::BoxType)
    if @dissect ref over |> HandleBound(handle = handle)
        if haskey(t.handle_map, handle)
            validate(vctx, over, t.handle_map[handle])
        else
            error()
        end
    else
        validate(vctx, ref, t.row)
    end
end

function validate(vctx::ValidateContext, ref::SQLNode)
    validate(vctx, ref, vctx.type)
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

function route(lt::BoxType, rt::BoxType, ref::SQLNode)
    if @dissect ref over |> HandleBound(handle = handle)
        lturn = haskey(lt.handle_map, handle)
        rturn = haskey(rt.handle_map, handle)
        @assert lturn != rturn
        return lturn ? -1 : 1
    else
        return route(lt.row, rt.row, ref)
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

gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::BoxNode) =
    gather!(vctx, refs, n.over)

function gather!(vctx::ValidateContext, refs::Vector{SQLNode}, n::Union{NameBoundNode, HandleBoundNode})
    validate(vctx, convert(SQLNode, n))
    push!(refs, n)
end


# Populating export list of SQL subqueries.

populate!(actx::AnnotateContext, n::SQLNode, req::BuildRequest) =
    populate!(actx, n[], req)

function populate!(actx::AnnotateContext, ns::Vector{SQLNode}, req::BuildRequest)
    for n in ns
        populate!(actx, n, req)
    end
end

function populate!(actx::AnnotateContext, ::Nothing, req::BuildRequest)
    nothing
end

populate!(actx::AnnotateContext, n::Union{AsNode, HighlightNode, NameBoundNode, HandleBoundNode, SortNode}, req::BuildRequest) =
    populate!(actx, n.over, req)

populate!(::AnnotateContext, ::Union{Nothing, FromNode, GetNode, LiteralNode, VariableNode}, ::BuildRequest) =
    nothing

populate!(actx::AnnotateContext, n::FunctionNode, req::BuildRequest) =
    populate!(actx, n.args, req)

function populate!(actx::AnnotateContext, n::AggregateNode, req::BuildRequest)
    populate!(actx, n.args, req)
    populate!(actx, n.filter, req)
end

function populate!(actx::AnnotateContext, n::BoxNode, req::BuildRequest)
    append!(n.refs, req.refs)
    refs′ = SQLNode[]
    for ref in req.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    populate!(actx, n.over, BuildRequest(req.ctx, refs = refs′))
end

function populate!(actx::AnnotateContext, n::AppendNode, req::BuildRequest)
    populate!(actx, n.over, req)
    for l in n.list
        populate!(actx, l, req)
    end
end

function populate!(actx::AnnotateContext, n::AsNode, req::BuildRequest)
    refs′ = SQLNode[]
    for ref in req.refs
        if @dissect ref over |> NameBound(name = name)
            @assert name == n.name
            push!(refs′, over)
        elseif @dissect ref HandleBound()
            push!(refs′, ref)
        else
            error()
        end
    end
    populate!(actx, n.over, BuildRequest(req.ctx, refs = refs′))
end

function populate!(actx::AnnotateContext, n::BindNode, req::BuildRequest)
    base_req = BuildRequest(req.ctx, refs = req.refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.list, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::DefineNode, req::BuildRequest)
    vctx = ValidateContext(actx, box_type(n.over))
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
    base_req = BuildRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.list, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::GroupNode, req::BuildRequest)
    vctx = ValidateContext(actx, box_type(n.over))
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
    base_req = BuildRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.by, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::HighlightNode, req::BuildRequest)
    populate!(actx, n.over, req)
end

function populate!(actx::AnnotateContext, n::ExtendedJoinNode, req::BuildRequest)
    vctx = ValidateContext(actx, n.type)
    lt = box_type(n.over)
    rt = box_type(n.joinee)
    refs = SQLNode[]
    gather!(vctx, refs, n.on)
    append!(refs, req.refs)
    lrefs = SQLNode[]
    rrefs = SQLNode[]
    for ref in refs
        turn = route(lt, rt, ref)
        if turn < 0
            push!(lrefs, ref)
        else
            push!(rrefs, ref)
        end
    end
    lvctx = ValidateContext(actx, lt)
    gather!(lvctx, n.lateral, n.joinee)
    append!(lrefs, n.lateral)
    populate!(actx, n.over, BuildRequest(req.ctx, refs = lrefs))
    populate!(actx, n.joinee, BuildRequest(req.ctx, refs = rrefs))
    populate!(actx, n.on, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::LimitNode, req::BuildRequest)
    populate!(actx, n.over, req)
end

function populate!(actx::AnnotateContext, n::OrderNode, req::BuildRequest)
    vctx = ValidateContext(actx, box_type(n.over))
    base_refs = copy(req.refs)
    gather!(vctx, base_refs, n.by)
    base_req = BuildRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.by, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::PartitionNode, req::BuildRequest)
    vctx = ValidateContext(actx, box_type(n.over))
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
    base_req = BuildRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.by, BuildRequest(req.ctx))
    populate!(actx, n.order_by, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::SelectNode, req::BuildRequest)
    vctx = ValidateContext(actx, box_type(n.over))
    base_refs = SQLNode[]
    gather!(vctx, base_refs, n.list)
    base_req = BuildRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.list, BuildRequest(req.ctx))
end

function populate!(actx::AnnotateContext, n::WhereNode, req::BuildRequest)
    vctx = ValidateContext(actx, box_type(n.over))
    base_refs = copy(req.refs)
    gather!(vctx, base_refs, n.condition)
    base_req = BuildRequest(req.ctx, refs = base_refs)
    populate!(actx, n.over, base_req)
    populate!(actx, n.condition, BuildRequest(req.ctx))
end


# Building SQL clauses.

build(n::SQLNode, ctx::BuildContext) =
    build(n[], ctx)

build(n::SQLNode, treq::TranslateRequest) =
    build(n[], treq)

function build(::Nothing, ctx::BuildContext)
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    BuildResult(c, repl)
end

build(n::SQLNode, ctx::Union{BuildContext, TranslateRequest}, refs::Vector{SQLNode}) =
    build(n[], ctx, refs)

build(n::SubqueryNode, treq::TranslateRequest, refs::Vector{SQLNode}) =
    build(n, treq.ctx, refs)

translate(n::BoxNode, treq::TranslateRequest) =
    build(n, treq).clause

function build(n::BoxNode, ctx::BuildContext)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = build(n.over, ctx, refs′)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    BuildResult(res.clause, repl′)
end

function build(n::BoxNode, treq::TranslateRequest)
    refs′ = SQLNode[]
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(handle = handle)) && handle == n.handle
            push!(refs′, over)
        else
            push!(refs′, ref)
        end
    end
    res = build(n.over, treq, refs′)
    repl′ = Dict{SQLNode, Symbol}()
    for ref in n.refs
        if (@dissect ref over |> HandleBoundNode(node = node)) && handle == n.handle
            repl′[ref] = res.repl[over]
        else
            repl′[ref] = res.repl[ref]
        end
    end
    BuildResult(res.clause, repl′)
end

function build(::Nothing, ctx::BuildContext, refs::Vector{SQLNode})
    c = SELECT(list = SQLClause[missing])
    repl = Dict{SQLNode, Symbol}()
    BuildResult(c, repl)
end

function build(n::AppendNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::AsNode, ctx::Union{BuildContext, TranslateRequest}, refs::Vector{SQLNode})
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
    BuildResult(res.clause, repl′)
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

build(n::BindNode, ctx::BuildContext, refs::Vector{SQLNode}) =
    build(n, TranslateRequest(ctx, Dict{SQLNode, SQLClause}()), refs)

function build(n::DefineNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::FromNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::GroupNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

build(n::HighlightNode, ctx::BuildContext, refs::Vector{SQLNode}) =
    build(n.over, ctx)

function build(n::ExtendedJoinNode, ctx::BuildContext, refs::Vector{SQLNode})
    left_res = build(n.over, ctx)
    left_as = allocate_alias(ctx, n.over)
    lateral = !isempty(n.lateral)
    if lateral
        lsubs = Dict{SQLNode, SQLClause}()
        for ref in n.lateral
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
    BuildResult(c, repl)
end

function build(n::LimitNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::OrderNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::PartitionNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::SelectNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

function build(n::WhereNode, ctx::BuildContext, refs::Vector{SQLNode})
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
    BuildResult(c, repl)
end

