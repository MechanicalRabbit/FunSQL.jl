# Variable reference.

mutable struct VariableNode <: AbstractSQLNode
    name::Symbol

    VariableNode(; name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

VariableNode(name) =
    VariableNode(name = name)

"""
    Var(; name)
    Var(name)
    Var.name        Var."name"      Var[name]       Var["name"]

A reference to a query parameter.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Where(Get.year_of_birth .> Var.year);

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."year_of_birth" > :year)
```
"""
Var(args...; kws...) =
    VariableNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Var), pats::Vector{Any}) =
    dissect(scr, VariableNode, pats)

Base.getproperty(::typeof(Var), name::Symbol) =
    Var(name)

Base.getproperty(::typeof(Var), name::AbstractString) =
    Var(name)

Base.getindex(::typeof(Var), name::Union{Symbol, AbstractString}) =
    Var(name)

PrettyPrinting.quoteof(n::VariableNode, ctx::QuoteContext) =
    Expr(:., nameof(Var), quoteof(n.name))

label(n::VariableNode) =
    n.name

