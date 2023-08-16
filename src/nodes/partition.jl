# Window partition.

mutable struct PartitionNode <: TabularNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}
    order_by::Vector{SQLNode}
    frame::Union{PartitionFrame, Nothing}
    name::Union{Symbol, Nothing}

    PartitionNode(;
                  over = nothing,
                  by = SQLNode[],
                  order_by = SQLNode[],
                  frame = nothing,
                  name::Union{Symbol, AbstractString, Nothing} = nothing) =
        new(over, by, order_by, frame, name !== nothing ? Symbol(name) : nothing)
end

PartitionNode(by...; over = nothing, order_by = SQLNode[], frame = nothing, name = nothing) =
    PartitionNode(over = over, by = SQLNode[by...], order_by = order_by, frame = frame, name = name)

"""
    Partition(; over, by = [], order_by = [], frame = nothing, name = nothing)
    Partition(by...; over, order_by = [], frame = nothing, name = nothing)

The `Partition` node relates adjacent rows.

Specifically, `Partition` specifies how to relate each row to the adjacent rows
in the same dataset.  The rows are partitioned `by` the given key and ordered
within each partition using `order_by` key.  The parameter `frame` customizes
the extent of related rows.  These related rows are summarized by aggregate
functions [`Agg`](@ref) applied to the output of `Partition`.  An optional
parameter `name` specifies the field to hold the partition.

The `Partition` node is translated to a query with a `WINDOW` clause:
```sql
SELECT ...
FROM \$over
WINDOW w AS (PARTITION BY \$by... ORDER BY \$order_by...)
```

# Examples

*Enumerate patients' visits.*

```jldoctest
julia> visit_occurrence =
           SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date]);

julia> q = From(:visit_occurrence) |>
           Partition(Get.person_id, order_by = [Get.visit_start_date]) |>
           Select(Agg.row_number(), Get.visit_occurrence_id);

julia> print(render(q, tables = [visit_occurrence]))
SELECT
  (row_number() OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number",
  "visit_occurrence_1"."visit_occurrence_id"
FROM "visit_occurrence" AS "visit_occurrence_1"
```

The same example using an explicit partition name.

```jldoctest
julia> visit_occurrence =
           SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date]);

julia> q = From(:visit_occurrence) |>
           Partition(Get.person_id, order_by = [Get.visit_start_date], name = :visit_by_person) |>
           Select(Get.visit_by_person |> Agg.row_number(), Get.visit_occurrence_id);

julia> print(render(q, tables = [visit_occurrence]))
SELECT
  (row_number() OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number",
  "visit_occurrence_1"."visit_occurrence_id"
FROM "visit_occurrence" AS "visit_occurrence_1"
```

*Calculate the moving average of the number of patients by the year of birth.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Group(Get.year_of_birth) |>
           Partition(order_by = [Get.year_of_birth],
                     frame = (mode = :range, start = -1, finish = 1)) |>
           Select(Get.year_of_birth, Agg.avg(Agg.count()));

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."year_of_birth",
  (avg(count(*)) OVER (ORDER BY "person_1"."year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING)) AS "avg"
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
    if n.name !== nothing
        push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::PartitionNode) =
    label(n.over)

rebase(n::PartitionNode, n′) =
    PartitionNode(over = rebase(n.over, n′), by = n.by, order_by = n.order_by, frame = n.frame, name = n.name)
