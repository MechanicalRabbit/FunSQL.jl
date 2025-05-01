# Grouping.

function populate_grouping_sets!(n, sets)
    for set in sets
        set′ = Int[]
        for el in set
            push!(set′, _grouping_index(el, n))
        end
        push!(n.sets, set′)
    end
end

_grouping_index(el::Integer, n) =
    convert(Int, el)

function _grouping_index(el::Symbol, n)
    k = get(n.label_map, el, nothing)
    if k == nothing
        throw(InvalidGroupingSetsError(el))
    end
    k
end

_grouping_index(el::AbstractString, n) =
    _grouping_index(Symbol(el), n)

struct GroupNode <: TabularNode
    by::Vector{SQLQuery}
    sets::Union{Vector{Vector{Int}}, GroupingMode, Nothing}
    name::Union{Symbol, Nothing}
    label_map::OrderedDict{Symbol, Int}

    function GroupNode(;
                       by = SQLQuery[],
                       sets = nothing,
                       name::Union{Symbol, AbstractString, Nothing} = nothing,
                       label_map = nothing)
        need_to_populate_sets = !(sets isa Union{Vector{Vector{Int}}, GroupingMode, Symbol, Nothing})
        n = new(
            by,
            need_to_populate_sets ? Vector{Int}[] : sets isa Symbol ? convert(GroupingMode, sets) : sets,
            name !== nothing ? Symbol(name) : nothing,
            label_map !== nothing ? label_map : OrderedDict{Symbol, Int}())
        if label_map === nothing
            populate_label_map!(n, n.by, n.label_map, n.name)
        end
        if need_to_populate_sets
            populate_grouping_sets!(n, sets)
        end
        if n.sets isa Vector{Vector{Int}}
            usage = falses(length(n.by))
            for set in n.sets
                for k in set
                    checkbounds(Bool, n.by, k) || throw(InvalidGroupingSetsError(k, path = [n]))
                    usage[k] = true
                end
            end
            all(usage) || throw(InvalidGroupingSetsError(collect(keys(n.label_map))[usage], path = [n]))
        end
        n
    end
end

GroupNode(by...; sets = nothing, name = nothing) =
    GroupNode(by = SQLQuery[by...], sets = sets, name = name)

"""
    Group(; by = [], sets = sets, name = nothing, tail = nothing)
    Group(by...; sets = sets, name = nothing, tail = nothing)

The `Group` node summarizes the input dataset.

Specifically, `Group` outputs all unique values of the given grouping key.
This key partitions the input rows into disjoint groups that are summarized
by aggregate functions [`Agg`](@ref) applied to the output of `Group`.  The
parameter `sets` specifies the grouping sets, either with grouping mode
indicators `:cube` or `:rollup`, or explicitly as `Vector{Vector{Symbol}}`.
An optional parameter `name` specifies the field to hold the group.

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
const Group = SQLQueryCtor{GroupNode}(:Group)

const funsql_group = Group

function PrettyPrinting.quoteof(n::GroupNode, ctx::QuoteContext)
    ex = Expr(:call, :Group, quoteof(n.by, ctx)...)
    s = n.sets
    if s !== nothing
        push!(ex.args, Expr(:kw, :sets, s isa GroupingMode ? QuoteNode(Symbol(s)) : s))
    end
    if n.name !== nothing
        push!(ex.args, Expr(:kw, :name, QuoteNode(n.name)))
    end
    ex
end
