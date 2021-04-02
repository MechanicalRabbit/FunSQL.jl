# Where node.

mutable struct WhereNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    condition::SQLNode

    WhereNode(; over = nothing, condition) =
        new(over, condition)
end

WhereNode(condition; over = nothing) =
    WhereNode(over = over, condition = condition)

"""
    Where(; over = nothing, condition)
    Where(condition; over = nothing)

A subquery that filters by the given `condition`.

```sql
SELECT ... FROM \$over WHERE \$condition
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Where(Call(">", Get.year_of_birth, 2000));

julia> print(render(q))
SELECT "person_2"."person_id", "person_2"."year_of_birth"
FROM (
  SELECT "person_1"."person_id", "person_1"."year_of_birth"
  FROM "person" AS "person_1"
) AS "person_2"
WHERE ("person_2"."year_of_birth" > 2000)
```
"""
Where(args...; kws...) =
    WhereNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::WhereNode; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call,
              wrap ? nameof(Where) : nameof(WhereNode),
              !limit ? quoteof(n.condition) : :…)
    if n.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(n.over), ex)
    end
    ex
end

rebase(n::WhereNode, n′) =
    WhereNode(over = rebase(n.over, n′), condition = n.condition)

alias(n::WhereNode) =
    alias(n.over)

star(n::WhereNode) =
    star(n.over)

function split_get(n::SQLNode, stop::SQLNode)
    core = n[]
    core isa GetNode || return n
    if core.over === stop
        return Get(name = core.name)
    end
    over′ = core.over !== nothing ?
        split_get(core.over, stop) :
        nothing
    over′ !== core.over ?
        Get(over = over′, name = core.name) :
        n
end

function resolve(n::WhereNode, req)
    rebases = Dict{SQLNode, SQLNode}()
    base_refs = SQLNode[]
    gather!(base_refs, n.condition)
    for ref in req.refs
        !(ref in keys(rebases)) || continue
        core = ref[]
        if core isa GetNode
            ref′ = split_get(ref, convert(SQLNode, n))
            if ref′ !== ref
                rebases[ref] = ref′
            end
            push!(base_refs, ref′)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    base_as = allocate_alias(req.ctx, n.over)
    subs = Dict{SQLNode, SQLClause}()
    for (ref, name) in base_res.repl
        subs[ref] = ID(over = base_as, name = name)
    end
    condition = translate(n.condition, subs)
    list = SQLClause[]
    repl = Dict{SQLNode, Symbol}()
    seen = Set{Symbol}()
    for ref in req.refs
        ref′ = get(rebases, ref, ref)
        if ref′ in keys(base_res.repl)
            name = base_res.repl[ref′]
            repl[ref] = name
            !(name in seen) || continue
            push!(seen, name)
            id = ID(over = base_as, name = name)
            push!(list, id)
        end
    end
    if isempty(list)
        push!(list, true)
    end
    w = WHERE(over = FROM(AS(over = base_res.clause, name = base_as)),
              condition = condition)
    c = SELECT(over = w, list = list)
    ResolveResult(c, repl)
end

