# Attribute lookup.

mutable struct GetNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    name::Symbol

    GetNode(;
            over = nothing,
            name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

GetNode(name; over = nothing) =
    GetNode(over = over, name = name)

"""
    Get(; over, name)
    Get(name; over)
    Get.name        Get."name"      Get[name]       Get["name"]
    over.name       over."name"     over[name]      over["name"]
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
Get(args...; kws...) =
    GetNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Get), pats::Vector{Any}) =
    dissect(scr, GetNode, pats)

Base.convert(::Type{AbstractSQLNode}, name::Symbol) =
    GetNode(name)

Base.getproperty(::typeof(Get), name::Symbol) =
    Get(name)

Base.getproperty(::typeof(Get), name::AbstractString) =
    Get(name)

Base.getindex(::typeof(Get), name::Union{Symbol, AbstractString}) =
    Get(name)

Base.getproperty(n::SQLNode, name::Symbol) =
    Get(name, over = n)

Base.getproperty(n::SQLNode, name::AbstractString) =
    Get(name, over = n)

Base.getindex(n::SQLNode, name::Union{Symbol, AbstractString}) =
    Get(name, over = n)

function PrettyPrinting.quoteof(n::GetNode, ctx::QuoteContext)
    path = Symbol[n.name]
    over = n.over
    while over !== nothing && (nested = over[]; nested isa GetNode) && !(over in keys(ctx.vars))
        push!(path, nested.name)
        over = nested.over
    end
    if over !== nothing && over in keys(ctx.vars)
        ex = ctx.vars[over]
        over = nothing
    else
        ex = nameof(Get)
    end
    while !isempty(path)
        name = pop!(path)
        ex = Expr(:., ex, quoteof(name))
    end
    if over !== nothing
        ex = Expr(:call, :|>, quoteof(over, ctx), ex)
    end
    ex
end

label(n::GetNode) =
    n.name
