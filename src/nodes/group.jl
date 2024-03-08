# Grouping.

mutable struct GroupNode <: TabularNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}
    sets::Union{Vector{Vector{Int}}, GroupingMode, Nothing}
    name::Union{Symbol, Nothing}
    label_map::OrderedDict{Symbol, Int}

    function GroupNode(;
                       over = nothing,
                       by = SQLNode[],
                       sets = nothing,
                       name::Union{Symbol, AbstractString, Nothing} = nothing,
                       label_map = nothing)
        n = new(
            over,
            by,
            sets isa Symbol ? convert(GroupingMode, sets) : sets,
            name !== nothing ? Symbol(name) : nothing,
            label_map !== nothing ? label_map : OrderedDict{Symbol, Int}())
        s = n.sets
        if s isa Vector{Vector{Int}} && !checkbounds(Bool, n.by, s)
            throw(DomainError(s, "sets are out of bounds"))
        end
        if label_map === nothing
            populate_label_map!(n, n.by, n.label_map, n.name)
        end
        n
    end
end

GroupNode(by...; over = nothing, sets = nothing, name = nothing) =
    GroupNode(over = over, by = SQLNode[by...], sets = sets, name = name)

"""
    Group(; over, by = [], sets = sets, name = nothing)
    Group(by...; over, sets = sets, name = nothing)

The `Group` node summarizes the input dataset.

Specifically, `Group` outputs all unique values of the given grouping key.
This key partitions the input rows into disjoint groups that are summarized
by aggregate functions [`Agg`](@ref) applied to the output of `Group`.  The
parameter `sets` customizes the grouping sets.  An optional parameter
`name` specifies the field to hold the group.

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

julia> q = From(:person) |>
           Group() |>
           Select(Agg.count());

julia> print(render(q, tables = [person]))
SELECT count(*) AS "count"
FROM "person" AS "person_1"
```

*Number of patients per year of birth.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Group(Get.year_of_birth) |>
           Select(Get.year_of_birth, Agg.count());

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."year_of_birth",
  count(*) AS "count"
FROM "person" AS "person_1"
GROUP BY "person_1"."year_of_birth"
```

The same example using an explicit group name.

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Group(Get.year_of_birth, name = :person) |>
           Select(Get.year_of_birth, Get.person |> Agg.count());

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."year_of_birth",
  count(*) AS "count"
FROM "person" AS "person_1"
GROUP BY "person_1"."year_of_birth"
```

*Number of patients per year of birth and the total number of patients.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Group(Get.year_of_birth, sets = :cube) |>
           Select(Get.year_of_birth, Agg.count());

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."year_of_birth",
  count(*) AS "count"
FROM "person" AS "person_1"
GROUP BY CUBE("person_1"."year_of_birth")
```

*Distinct states across all available locations.*

```jldoctest
julia> location = SQLTable(:location, columns = [:location_id, :state]);

julia> q = From(:location) |>
           Group(Get.state);

julia> print(render(q, tables = [location]))
SELECT DISTINCT "location_1"."state"
FROM "location" AS "location_1"
```
"""
Group(args...; kws...) =
    GroupNode(args...; kws...) |> SQLNode

const funsql_group = Group

dissect(scr::Symbol, ::typeof(Group), pats::Vector{Any}) =
    dissect(scr, GroupNode, pats)

function PrettyPrinting.quoteof(n::GroupNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Group), quoteof(n.by, ctx)...)
    s = n.sets
    if s !== nothing
        push!(ex.args, Expr(:kw, :sets, s isa GroupingMode ? QuoteNode(Symbol(s)) : s))
    end
    if n.name !== nothing
        push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end
