# Grouping.

mutable struct GroupNode <: TabularNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function GroupNode(; over = nothing, by = SQLNode[], label_map = nothing)
        if label_map !== nothing
            new(over, by, label_map)
        else
            n = new(over, by, OrderedDict{Symbol, Int}())
            populate_label_map!(n, n.by, n.label_map)
            n
        end
    end
end

GroupNode(by...; over = nothing) =
    GroupNode(over = over, by = SQLNode[by...])

"""
    Group(; over; by = [])
    Group(by...; over)

The `Group` node summarizes the input dataset.

Specifically, `Group` outputs all unique values of the given grouping key.
This key partitions the input rows into disjoint groups that are summarized
by aggregate functions [`Agg`](@ref) applied to the output of `Group`.

The `Group` node is translated to a SQL query with a `GROUP BY` clause:
```sql
SELECT ...
FROM \$over
GROUP BY \$by...
```

# Examples

*Total number of patients.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group() |>
           Select(Agg.count());

julia> print(render(q))
SELECT COUNT(*) AS "count"
FROM "person" AS "person_1"
```

*Number of patients per year of birth.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group(Get.year_of_birth) |>
           Select(Get.year_of_birth, Agg.count());

julia> print(render(q))
SELECT
  "person_1"."year_of_birth",
  COUNT(*) AS "count"
FROM "person" AS "person_1"
GROUP BY "person_1"."year_of_birth"
```

*Distinct states among all available locations.*

```jldoctest
julia> location = SQLTable(:location, columns = [:location_id, :state]);

julia> q = From(location) |>
           Group(Get.state);

julia> print(render(q))
SELECT DISTINCT "location_1"."state"
FROM "location" AS "location_1"
```
"""
Group(args...; kws...) =
    GroupNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Group), pats::Vector{Any}) =
    dissect(scr, GroupNode, pats)

function PrettyPrinting.quoteof(n::GroupNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Group), quoteof(n.by, ctx)...)
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::GroupNode) =
    label(n.over)

rebase(n::GroupNode, n′) =
    GroupNode(over = rebase(n.over, n′), by = n.by, label_map = n.label_map)

