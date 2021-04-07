# From node.

mutable struct FromNode <: SubqueryNode
    table::SQLTable

    FromNode(; table) =
        new(table)
end

FromNode(table) =
    FromNode(table = table)

"""
    From(; table)
    From(table)

A subquery that selects columns from the given table.

```sql
SELECT ... FROM \$table
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
```
"""
From(args...; kws...) =
    FromNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(From), pats::Vector{Any}) =
    dissect(scr, FromNode, pats)

Base.convert(::Type{AbstractSQLNode}, table::SQLTable) =
    FromNode(table)

function PrettyPrinting.quoteof(n::FromNode, qctx::SQLNodeQuoteContext)
    tex = get(qctx.vars, n.table, nothing)
    if tex === nothing
        tex = quoteof(n.table, limit = true)
    end
    Expr(:call, nameof(From), tex)
end

