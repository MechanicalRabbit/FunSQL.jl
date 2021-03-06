# Sorting.

mutable struct OrderNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}

    OrderNode(; over = nothing, by) =
        new(over, by)
end

OrderNode(by...; over = nothing) =
    OrderNode(over = over, by = SQLNode[by...])

"""
    Order(; over = nothing, by)
    Order(by...; over = nothing)

A subquery that sorts the rows `by` a list of keys.

```sql
SELECT ...
FROM \$over
ORDER BY \$by...
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Order(Get.year_of_birth) |>
           Select(Get.person_id);

julia> print(render(q))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth"
```
"""
Order(args...; kws...) =
    OrderNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Order), pats::Vector{Any}) =
    dissect(scr, OrderNode, pats)

function PrettyPrinting.quoteof(n::OrderNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Order))
    if isempty(n.by)
        push!(ex.args, Expr(:kw, :by, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.by, qctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::OrderNode, n′) =
    OrderNode(over = rebase(n.over, n′), by = n.by)

