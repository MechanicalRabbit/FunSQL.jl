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
SELECT "person_2"."person_id", "person_2"."year_of_birth"
FROM (
  SELECT "person_1"."person_id", "person_1"."year_of_birth"
  FROM "person" AS "person_1"
) AS "person_2"
WHERE (NOT ("person_2"."person_id" > 2000))
```
"""
Call(args...; kws...) =
    CallNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::CallNode; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call,
              wrap ? nameof(Call) : nameof(CallNode),
              string(n.name))
    if !limit || isempty(n.args)
        args_exs = Any[quoteof(arg) for arg in n.args]
        append!(ex.args, args_exs)
    else
        push!(ex.args, :…)
    end
    ex
end

alias(n::CallNode) =
    n.name

gather!(refs::Vector{SQLNode}, n::CallNode) =
    gather!(refs, n.args)

translate(n::CallNode, subs) =
    OP(n.name, args = SQLClause[translate(arg, subs) for arg in n.args])

