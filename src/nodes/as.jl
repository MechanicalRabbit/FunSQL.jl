# AS wrapper.

mutable struct AsNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    name::Symbol

    AsNode(;
           over = nothing,
           name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

AsNode(name; over = nothing) =
    AsNode(over = over, name = name)

"""
    As(; over = nothing, name)
    As(name; over = nothing)
    name => over

`As` specifies the name of the output column.

The arrow operator (`=>`) is a shorthand notation for `As`.

# Examples

*Show all patient IDs.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |> Select(:id => Get.person_id);

julia> print(render(q, tables = [person]))
SELECT "person_1"."person_id" AS "id"
FROM "person" AS "person_1"
```

*Show all patients together with their primary care provider.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth, :provider_id]);

julia> provider = SQLTable(:provider, columns = [:provider_id, :provider_name]);

julia> q = From(:person) |>
           Join(From(:provider) |> As(:pcp),
                on = Get.provider_id .== Get.pcp.provider_id) |>
           Select(Get.person_id, Get.pcp.provider_name);

julia> print(render(q, tables = [person, provider]))
SELECT
  "person_1"."person_id",
  "location_1"."state"
FROM "person" AS "person_1"
JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
```
"""
As(args...; kws...) =
    AsNode(args...; kws...) |> SQLNode

const funsql_as = As

dissect(scr::Symbol, ::typeof(As), pats::Vector{Any}) =
    dissect(scr, AsNode, pats)

Base.convert(::Type{AbstractSQLNode}, p::Pair{<:Union{Symbol, AbstractString}}) =
    AsNode(name = first(p), over = convert(SQLNode, last(p)))

function PrettyPrinting.quoteof(n::AsNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(As), quoteof(n.name))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::AsNode) =
    n.name
