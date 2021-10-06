# Selecting.

mutable struct SelectNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function SelectNode(; over = nothing, list, label_map = nothing)
        if label_map !== nothing
            return new(over, list, label_map)
        end
        n = new(over, list, OrderedDict{Symbol, Int}())
        for (i, l) in enumerate(n.list)
            name = label(l)
            if name in keys(n.label_map)
                err = DuplicateAliasError(name, stack = [l, n])
                throw(err)
            end
            n.label_map[name] = i
        end
        n
    end
end

SelectNode(list...; over = nothing) =
    SelectNode(over = over, list = SQLNode[list...])

"""
    Select(; over; list)
    Select(list...; over)

A subquery that fixes the `list` of output columns.

```sql
SELECT \$list...
FROM \$over
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Select(Get.person_id);

julia> print(render(q))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
```
"""
Select(args...; kws...) =
    SelectNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Select), pats::Vector{Any}) =
    dissect(scr, SelectNode, pats)

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

label(n::SelectNode) =
    label(n.over)

rebase(n::SelectNode, n′) =
    SelectNode(over = rebase(n.over, n′), list = n.list, label_map = n.label_map)

