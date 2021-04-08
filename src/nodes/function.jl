# Function and operator calls.

mutable struct FunctionNode <: AbstractSQLNode
    name::Symbol
    args::Vector{SQLNode}

    FunctionNode(;
             name::Union{Symbol, AbstractString},
             args = SQLNode[]) =
        new(Symbol(name), args)
end

FunctionNode(name; args = SQLNode[]) =
    FunctionNode(name = name, args = args)

FunctionNode(name, args...) =
    FunctionNode(name = name, args = SQLNode[args...])

"""
    Fun(; name, args = [])
    Fun(name; args = [])
    Fun(name, args...)

A function or an operator invocation.

# Example

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Where(Fun("NOT", Fun(">", Get.person_id, 2000)));

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE (NOT ("person_1"."person_id" > 2000))
```
"""
Fun(args...; kws...) =
    FunctionNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Fun), pats::Vector{Any}) =
    dissect(scr, FunctionNode, pats)

PrettyPrinting.quoteof(n::FunctionNode, qctx::SQLNodeQuoteContext) =
    Expr(:call, nameof(Fun), string(n.name), quoteof(n.args, qctx)...)

