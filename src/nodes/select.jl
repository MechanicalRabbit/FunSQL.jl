# Selecting.

struct SelectNode <: TabularNode
    args::Vector{SQLQuery}
    label_map::OrderedDict{Symbol, Int}

    function SelectNode(; args, label_map = nothing)
        if label_map !== nothing
            new(args, label_map)
        else
            n = new(args, OrderedDict{Symbol, Int}())
            populate_label_map!(n)
            n
        end
    end
end

SelectNode(args...) =
    SelectNode(args = SQLQuery[args...])

"""
    Select(; args, tail = nothing)
    Select(args...; tail = nothing)

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

julia> q = From(:person) |>
           Select(Get.person_id,
                  :age => Fun.now() .- Get.birth_datetime);

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  (now() - "person_1"."birth_datetime") AS "age"
FROM "person" AS "person_1"
```
"""
const Select = SQLQueryCtor{SelectNode}(:Select)

const funsql_select = Select

function PrettyPrinting.quoteof(n::SelectNode, ctx::QuoteContext)
    ex = Expr(:call, :Select)
    if isempty(n.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.args, ctx))
    end
    ex
end
