# Defining calculated columns.

mutable struct DefineNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function DefineNode(; over = nothing, args = [], label_map = nothing)
        if label_map !== nothing
            return new(over, args, label_map)
        end
        n = new(over, args, OrderedDict{Symbol, Int}())
        for (i, arg) in enumerate(n.args)
            name = label(arg)
            if name in keys(n.label_map)
                err = DuplicateLabelError(name, path = [arg, n])
                throw(err)
            end
            n.label_map[name] = i
        end
        n
    end
end

DefineNode(args...; over = nothing) =
    DefineNode(over = over, args = SQLNode[args...])

"""
    Define(; over; args = [])
    Define(args...; over)

`Define` adds a column to the output.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :birth_datetime]);

julia> q = From(person) |>
           Define(:age => Fun.now() .- Get.birth_datetime) |>
           Where(Get.age .> "16 years");

julia> print(render(q))
SELECT
  "person_1"."person_id",
  "person_1"."birth_datetime",
  (NOW() - "person_1"."birth_datetime") AS "age"
FROM "person" AS "person_1"
WHERE ((NOW() - "person_1"."birth_datetime") > '16 years')
```
"""
Define(args...; kws...) =
    DefineNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Define), pats::Vector{Any}) =
    dissect(scr, DefineNode, pats)

function PrettyPrinting.quoteof(n::DefineNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Define), quoteof(n.args, ctx)...)
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::DefineNode) =
    label(n.over)

rebase(n::DefineNode, n′) =
    DefineNode(over = rebase(n.over, n′), args = n.args, label_map = n.label_map)

