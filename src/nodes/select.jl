# Selecting.

mutable struct SelectNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function SelectNode(; over = nothing, args, label_map = nothing)
        if label_map !== nothing
            new(over, args, label_map)
        else
            n = new(over, args, OrderedDict{Symbol, Int}())
            populate_label_map!(n)
            n
        end
    end
end

SelectNode(args...; over = nothing) =
    SelectNode(over = over, args = SQLNode[args...])

"""
    Select(; over; args)
    Select(args...; over)

The `Select` node specifies the output columns.

```sql
SELECT \$args...
FROM \$over
```

Set the column labels with [`As`](@ref).

# Examples

*List patient IDs and their age.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :birth_datetime]);

julia> q = From(person) |>
           Select(Get.person_id,
                  :age => Fun.now() .- Get.birth_datetime);

julia> print(render(q))
SELECT
  "person_1"."person_id",
  (NOW() - "person_1"."birth_datetime") AS "age"
FROM "person" AS "person_1"
```
"""
Select(args...; kws...) =
    SelectNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Select), pats::Vector{Any}) =
    dissect(scr, SelectNode, pats)

function PrettyPrinting.quoteof(n::SelectNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Select))
    if isempty(n.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.args, ctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::SelectNode) =
    label(n.over)

rebase(n::SelectNode, n′) =
    SelectNode(over = rebase(n.over, n′), args = n.args, label_map = n.label_map)

