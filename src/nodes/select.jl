# Selecting.

mutable struct SelectNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}

    SelectNode(; over = nothing, list) =
        new(over, list)
end

SelectNode(list...; over = nothing) =
    SelectNode(over = over, list = SQLNode[list...])

"""
    Select(; over; list)
    Select(list...; over)

A subquery that fixes the `list` of output columns.

```sql
SELECT \$list... FROM \$over
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Select(Get.person_id);

julia> print(render(q))
SELECT "person_2"."person_id"
FROM (
  SELECT "person_1"."person_id"
  FROM "person" AS "person_1"
) AS "person_2"
```
"""
Select(args...; kws...) =
    SelectNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::SelectNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Select))
    if isempty(n.list)
        push!(ex.args, Expr(:kw, :list, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.list, qctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::SelectNode, n′) =
    SelectNode(over = rebase(n.over, n′), list = n.list)

function visit(f, n::SelectNode)
    visit(f, n.over)
    visit(f, n.list)
end

function substitute(n::SelectNode, c::SQLNode, c′::SQLNode)
    if c === n.over
        SelectNode(over = c′, list = n.list)
    else
        list′ = substitute(n.list, c, c′)
        list′ !== n.list ?
            SelectNode(over = n.over, list = list′) :
            n
    end
end

alias(n::SelectNode) =
    alias(n.over)

star(n::SelectNode) =
    SQLNode[Get(over = n, name = alias(col)) for col in n.list]

function resolve(n::SelectNode, req)
    aliases = Symbol[alias(col) for col in n.list]
    indexes = Dict{Symbol, Int}()
    for (i, alias) in enumerate(aliases)
        if alias in keys(indexes)
            ex = DuplicateAliasError(alias)
            push!(ex.stack, n.list[i])
            throw(ex)
        end
        indexes[alias] = i
    end
    base_refs = SQLNode[]
    output_indexes = Set{Int}()
    for ref in req.refs
        core = ref[]
        if core isa GetNode && (core.over === nothing || core.over[] === n)
            if core.name in keys(indexes)
                push!(output_indexes, indexes[core.name])
            end
        end
    end
    for (i, col) in enumerate(n.list)
        if i in output_indexes
            gather!(base_refs, col)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    list = SQLClause[]
    for (i, col) in enumerate(n.list)
        i in output_indexes || continue
        c = translate(col, subs)
        if !(core = c[]; core isa IdentifierClause && core.name === aliases[i])
            c = AS(over = c, name = aliases[i])
        end
        push!(list, c)
    end
    if isempty(list)
        push!(list, true)
    end
    c = SELECT(over = FROM(AS(over = base_res.clause, name = base_as)),
               list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in req.refs
        core = ref[]
        if core isa GetNode && (core.over === nothing || core.over[] === n)
            if core.name in keys(indexes)
                repl[ref] = core.name
            end
        end
    end
    ResolveResult(c, repl)
end

