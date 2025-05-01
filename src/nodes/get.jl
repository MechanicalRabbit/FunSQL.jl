# Attribute lookup.

struct GetNode <: AbstractSQLNode
    name::Symbol

    GetNode(;
            name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

GetNode(name) =
    GetNode(name = name)

"""
    Get(; name, tail = nothing)
    Get(name; tail = nothing)
    Get.name        Get."name"      Get[name]       Get["name"]
    name

A reference to a column of the input dataset.

When a column reference is ambiguous (e.g., with [`Join`](@ref)), use
[`As`](@ref) to disambiguate the columns, and a chained `Get` node
(`Get.a.b.….z`) to refer to a column wrapped with `… |> As(:b) |> As(:a)`.

# Examples

*List patient IDs.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Select(Get(:person_id));

julia> print(render(q, tables = [person]))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
```

*Show patients with their state of residence.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id]);

julia> location = SQLTable(:location, columns = [:location_id, :state]);

julia> q = From(:person) |>
           Join(From(:location) |> As(:location),
                on = Get.location_id .== Get.location.location_id) |>
           Select(Get.person_id, Get.location.state);

julia> print(render(q, tables = [person, location]))
SELECT
  "person_1"."person_id",
  "location_1"."state"
FROM "person" AS "person_1"
JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
```
"""
const Get = SQLQueryCtor{GetNode}(:Get)

Base.convert(::Type{SQLQuery}, name::Symbol) =
    SQLQuery(GetNode(name))

Base.convert(::Type{SQLQuery}, q::SQLGetQuery) =
    SQLQuery(getfield(q, :tail), GetNode(getfield(q, :head)))

Base.getproperty(::typeof(Get), name::Symbol) =
    SQLGetQuery(nothing, Symbol(name))

Base.getproperty(::typeof(Get), name::AbstractString) =
    SQLGetQuery(nothing, Symbol(name))

Base.getindex(::typeof(Get), name::Union{Symbol, AbstractString}) =
    SQLGetQuery(nothing, Symbol(name))

function PrettyPrinting.quoteof(n::GetNode, ctx::QuoteContext)
    Expr(:., :Get, QuoteNode(n.name))
end

label(n::GetNode) =
    n.name
