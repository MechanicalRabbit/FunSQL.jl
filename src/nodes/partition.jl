# Window partition.

mutable struct PartitionNode <: SubqueryNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}
    order_by::Vector{SQLNode}

    PartitionNode(; over = nothing, by = SQLNode[], order_by = SQLNode[]) =
        new(over, by, order_by)
end

PartitionNode(by...; over = nothing, order_by = SQLNode[]) =
    PartitionNode(over = over, by = SQLNode[by...], order_by = order_by)

"""
    Partition(; over; by = [], order_by = [])
    Partition(by...; over, order_by = [])

A subquery that partitions rows `by` a list of keys.

```sql
SELECT ... FROM \$over WINDOW w AS (PARTITION BY \$by... ORDER BY \$order_by...)
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Partition(Get.year_of_birth) |>
           Select(Get.year_of_birth, Agg.row_number());

julia> print(render(q))
SELECT "person_1"."year_of_birth", (ROW_NUMBER() OVER (PARTITION BY "person_1"."year_of_birth")) AS "row_number"
FROM "person" AS "person_1"
```
"""
Partition(args...; kws...) =
    PartitionNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Partition), pats::Vector{Any}) =
    dissect(scr, PartitionNode, pats)

function PrettyPrinting.quoteof(n::PartitionNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(Partition), quoteof(n.by, qctx)...)
    if !isempty(n.order_by)
        push!(ex.args, Expr(:kw, :order_by, Expr(:vect, quoteof(n.order_by, qctx)...)))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::PartitionNode, n′) =
    PartitionNode(over = rebase(n.over, n′), by = n.by, order_by = n.order_by)

