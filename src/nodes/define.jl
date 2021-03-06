# Defining calculated columns.

mutable struct DefineNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    list::Vector{SQLNode}

    DefineNode(; over = nothing, list = []) =
        new(over, list)
end

DefineNode(list...; over = nothing) =
    DefineNode(over = over, list = SQLNode[list...])

"""
    Define(; over; list = [])
    Define(list...; over)

A subquery that defines calculated columns.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :birth_datetime]);

julia> q = From(person) |>
           Define(:age => Fun.now() .- Get.birth_datetime) |>
           Where(Get.age .> "16 years") |>
           Select(Get.person_id, Get.age);

julia> print(render(q))
SELECT "person_1"."person_id", (NOW() - "person_1"."birth_datetime") AS "age"
FROM "person" AS "person_1"
WHERE ((NOW() - "person_1"."birth_datetime") > '16 years')
```
"""
Define(args...; kws...) =
    DefineNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Define), pats::Vector{Any}) =
    dissect(scr, DefineNode, pats)

function PrettyPrinting.quoteof(n::DefineNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Define), quoteof(n.list, qctx)...)
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::DefineNode, n′) =
    DefineNode(over = rebase(n.over, n′), list = n.list)

