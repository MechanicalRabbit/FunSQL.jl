# Selecting.

mutable struct SelectNode <: SubqueryNode
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

rebase(n::SelectNode, n′) =
    SelectNode(over = rebase(n.over, n′), list = n.list)

