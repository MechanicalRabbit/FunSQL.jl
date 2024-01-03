# Defining calculated columns.

mutable struct DefineNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function DefineNode(; over = nothing, args = [], label_map = nothing)
        if label_map !== nothing
            new(over, args, label_map)
        else
            n = new(over, args, OrderedDict{Symbol, Int}())
            populate_label_map!(n)
            n
        end
    end
end

DefineNode(args...; over = nothing) =
    DefineNode(over = over, args = SQLNode[args...])

"""
    Define(; over; args = [])
    Define(args...; over)

The `Define` node adds or replaces output columns.

# Examples

*Show patients who are at least 16 years old.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :birth_datetime]);

julia> q = From(:person) |>
           Define(:age => Fun.now() .- Get.birth_datetime) |>
           Where(Get.age .>= "16 years");

julia> print(render(q, tables = [person]))
SELECT
  "person_2"."person_id",
  "person_2"."birth_datetime",
  "person_2"."age"
FROM (
  SELECT
    "person_1"."person_id",
    "person_1"."birth_datetime",
    (now() - "person_1"."birth_datetime") AS "age"
  FROM "person" AS "person_1"
) AS "person_2"
WHERE ("person_2"."age" >= '16 years')
```

*Conceal the year of birth of patients born before 1930.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Define(:year_of_birth => Fun.case(Get.year_of_birth .>= 1930,
                                             Get.year_of_birth,
                                             missing));

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  (CASE WHEN ("person_1"."year_of_birth" >= 1930) THEN "person_1"."year_of_birth" ELSE NULL END) AS "year_of_birth"
FROM "person" AS "person_1"
```
"""
Define(args...; kws...) =
    DefineNode(args...; kws...) |> SQLNode

const funsql_define = Define

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
