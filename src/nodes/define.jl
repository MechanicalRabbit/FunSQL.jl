# Defining calculated columns.

struct DefineNode <: TabularNode
    args::Vector{SQLQuery}
    before::Union{Symbol, Bool}
    after::Union{Symbol, Bool}
    label_map::OrderedDict{Symbol, Int}

    function DefineNode(; args = [], before = nothing, after = nothing, label_map = nothing)
        if label_map !== nothing
            n = new(args, something(before, false), something(after, false), label_map)
        else
            n = new(args, something(before, false), something(after, false), OrderedDict{Symbol, Int}())
            populate_label_map!(n)
        end
        if (n.before isa Symbol || n.before) && (n.after isa Symbol || n.after)
            throw(DomainError((before = n.before, after = n.after), "only one of `before` and `after` could be set"))
        end
        n
    end
end

DefineNode(args...; before = nothing, after = nothing) =
    DefineNode(args = SQLQuery[args...], before = before, after = after)

"""
    Define(; args = [], before = nothing, after = nothing, tail = nothing)
    Define(args...; before = nothing, after = nothing, tail = nothing)

The `Define` node adds or replaces output columns.

By default, new columns are added at the end of the column list while replaced
columns retain their position.  Set `after = true` (`after = <column>`) to add
both new and replaced columns at the end (after a specified column).
Alternatively, set `before = true` (`before = <column>`) to add both new and
replaced columns at the front (before the specified column).

# Examples

*Show patients who are at least 16 years old.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :birth_datetime]);

julia> q = From(:person) |>
           Define(:age => Fun.now() .- Get.birth_datetime, before = :birth_datetime) |>
           Where(Get.age .>= "16 years");

julia> print(render(q, tables = [person]))
SELECT
  "person_2"."person_id",
  "person_2"."age",
  "person_2"."birth_datetime"
FROM (
  SELECT
    "person_1"."person_id",
    (now() - "person_1"."birth_datetime") AS "age",
    "person_1"."birth_datetime"
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
const Define = SQLQueryCtor{DefineNode}(:Define)

const funsql_define = Define

function PrettyPrinting.quoteof(n::DefineNode, ctx::QuoteContext)
    ex = Expr(:call, :Define, quoteof(n.args, ctx)...)
    if n.before !== false
        push!(ex.args, Expr(:kw, :before, n.before isa Symbol ? QuoteNode(n.before) : n.before))
    end
    if n.after !== false
        push!(ex.args, Expr(:kw, :after, n.after isa Symbol ? QuoteNode(n.after) : n.after))
    end
    ex
end
