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
           Where(Fun.not(Get.person_id .> 2000));

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
    Expr(:call,
         Expr(:., nameof(Fun),
                  QuoteNode(Base.isidentifier(n.name) ? n.name : string(n.name))),
         quoteof(n.args, qctx)...)

label(n::FunctionNode) =
    n.name


# Notation for making function nodes.

struct FunClosure
    name::Symbol
end

Base.show(io::IO, f::FunClosure) =
    print(io, Expr(:., nameof(Fun),
                       QuoteNode(Base.isidentifier(f.name) ? f.name : string(f.name))))

Base.getproperty(::typeof(Fun), name::Symbol) =
    FunClosure(name)

Base.getproperty(::typeof(Fun), name::AbstractString) =
    FunClosure(Symbol(name))

(f::FunClosure)(args...) =
    Fun(f.name, args = SQLNode[args...])

(f::FunClosure)(; args = SQLNode[]) =
    Fun(f.name, args = args)


# Broadcasting notation.

struct FunStyle <: Base.BroadcastStyle
end

Base.BroadcastStyle(::Type{<:AbstractSQLNode}) =
    FunStyle()

Base.BroadcastStyle(::FunStyle, ::Base.Broadcast.DefaultArrayStyle{0}) =
    FunStyle()

Base.broadcastable(n::AbstractSQLNode) =
    n

Base.Broadcast.instantiate(bc::Base.Broadcast.Broadcasted{FunStyle}) =
    bc

Base.copy(bc::Base.Broadcast.Broadcasted{FunStyle}) =
    Fun(nameof(bc.f), args = SQLNode[bc.args...])

Base.convert(::Type{AbstractSQLNode}, bc::Base.Broadcast.Broadcasted{FunStyle}) =
    FunctionNode(nameof(bc.f), args = SQLNode[bc.args...])

