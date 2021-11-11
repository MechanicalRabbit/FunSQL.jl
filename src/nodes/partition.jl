# Window partition.

mutable struct PartitionNode <: TabularNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}
    order_by::Vector{SQLNode}
    frame::Union{PartitionFrame, Nothing}

    PartitionNode(; over = nothing, by = SQLNode[], order_by = SQLNode[], frame = nothing) =
        new(over, by, order_by, frame)
end

PartitionNode(by...; over = nothing, order_by = SQLNode[], frame = nothing) =
    PartitionNode(over = over, by = SQLNode[by...], order_by = order_by, frame = frame)

"""
    Partition(; over, by = [], order_by = [], frame = nothing)
    Partition(by...; over, order_by = [], frame = nothing)

A subquery that partitions rows `by` a list of keys.

```sql
SELECT ...
FROM \$over
WINDOW w AS (PARTITION BY \$by... ORDER BY \$order_by...)
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

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group(Get.year_of_birth) |>
           Partition(order_by = [Get.year_of_birth],
                     frame = (mode = :range, start = -1, finish = 1)) |>
           Select(Get.year_of_birth, Agg.avg(Agg.count()));

julia> print(render(q))
SELECT "person_1"."year_of_birth", (AVG(COUNT(*)) OVER (ORDER BY "person_1"."year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING)) AS "avg"
FROM "person" AS "person_1"
GROUP BY "person_1"."year_of_birth"
```
"""
Partition(args...; kws...) =
    PartitionNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Partition), pats::Vector{Any}) =
    dissect(scr, PartitionNode, pats)

function PrettyPrinting.quoteof(n::PartitionNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Partition), quoteof(n.by, ctx)...)
    if !isempty(n.order_by)
        push!(ex.args, Expr(:kw, :order_by, Expr(:vect, quoteof(n.order_by, ctx)...)))
    end
    if n.frame !== nothing
        push!(ex.args, Expr(:kw, :frame, quoteof(n.frame)))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::PartitionNode) =
    label(n.over)

rebase(n::PartitionNode, n′) =
    PartitionNode(over = rebase(n.over, n′), by = n.by, order_by = n.order_by, frame = n.frame)

