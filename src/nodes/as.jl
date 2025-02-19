# AS wrapper.

struct AsNode <: AbstractSQLNode
    name::Symbol

    AsNode(;
           name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

AsNode(name) =
    AsNode(name = name)

"""
    As(; name, tail = nothing)
    As(name; tail = nothing)
    name => tail

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
const As = SQLQueryCtor{AsNode}(:As)

const funsql_as = As

Base.convert(::Type{SQLQuery}, p::Pair{<:Union{Symbol, AbstractString}}) =
    SQLQuery(last(p), AsNode(name = first(p)))

function PrettyPrinting.quoteof(n::AsNode, ctx::QuoteContext)
    Expr(:call, :As, quoteof(n.name))
end

label(n::AsNode) =
    n.name
