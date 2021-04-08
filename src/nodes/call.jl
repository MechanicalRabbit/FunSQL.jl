# Function and operator calls.

mutable struct CallNode <: AbstractSQLNode
    name::Symbol
    args::Vector{SQLNode}

    CallNode(;
             name::Union{Symbol, AbstractString},
             args = SQLNode[]) =
        new(Symbol(name), args)
end

CallNode(name; args = SQLNode[]) =
    CallNode(name = name, args = args)

CallNode(name, args...) =
    CallNode(name = name, args = SQLNode[args...])

"""
    Call(; name, args = [])
    Call(name; args = [])
    Call(name, args...)

A function or an operator invocation.

# Example

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Where(Call("NOT", Call(">", Get.person_id, 2000)));

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE (NOT ("person_1"."person_id" > 2000))
```
"""
Call(args...; kws...) =
    CallNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Call), pats::Vector{Any}) =
    dissect(scr, CallNode, pats)

PrettyPrinting.quoteof(n::CallNode, qctx::SQLNodeQuoteContext) =
    Expr(:call, nameof(Call), string(n.name), quoteof(n.args, qctx)...)
