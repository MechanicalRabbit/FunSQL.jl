# Sort ordering.

struct SortNode <: AbstractSQLNode
    value::ValueOrder
    nulls::Union{NullsOrder, Nothing}

    SortNode(;
             value,
             nulls = nothing) =
        new(value, nulls)
end

SortNode(value; nulls = nothing) =
    SortNode(; value, nulls)

"""
    Sort(; value, nulls = nothing, tail = nothing)
    Sort(value; nulls = nothing, tail = nothing)
    Asc(; nulls = nothing, tail = nothing)
    Desc(; nulls = nothing, tail = nothing)

Sort order indicator.

Use with [`Order`](@ref) or [`Partition`](@ref) nodes.

# Examples

*List patients ordered by their age.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Order(Get.year_of_birth |> Desc(nulls = :first));

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth" DESC NULLS FIRST
```
"""
const Sort = SQLQueryCtor{SortNode}(:Sort)

"""
    Asc(; over = nothing, nulls = nothing)

Ascending order indicator.
"""
Asc(; kws...) =
    Sort(VALUE_ORDER.ASC; kws...)

"""
    Desc(; over = nothing, nulls = nothing)

Descending order indicator.
"""
Desc(; kws...) =
    Sort(VALUE_ORDER.DESC; kws...)

const funsql_sort = Sort

const funsql_asc = Asc

const funsql_desc = Desc

function PrettyPrinting.quoteof(n::SortNode, ctx::QuoteContext)
    if n.value == VALUE_ORDER.ASC
        ex = Expr(:call, :Asc)
    elseif n.value == VALUE_ORDER.DESC
        ex = Expr(:call, :Desc)
    else
        ex = Expr(:call, :Sort, QuoteNode(Symbol(n.value)))
    end
    if n.nulls !== nothing
        push!(ex.args, Expr(:kw, :nulls, QuoteNode(Symbol(n.nulls))))
    end
    ex
end
