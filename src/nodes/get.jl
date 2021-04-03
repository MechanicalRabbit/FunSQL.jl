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

A reference to a table column, or an aliased expression or subquery.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           As(:p) |>
           Select(Get.p.person_id);
```

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> q = q |> Select(q.person_id);
```
"""
Get(args...; kws...) =
    GetNode(args...; kws...) |> SQLNode

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

function PrettyPrinting.quoteof(n::GetNode; limit::Bool = false, wrap::Bool = false)
    if !wrap
        ex = Expr(:call, nameof(GetNode), quoteof(n.name))
        if n.over !== nothing
            ex = Expr(:call, :|>, limit ? :… : quoteof(n.over), ex)
        end
        return ex
    end
    path = Symbol[n.name]
    over = n.over
    while over !== nothing && (n′ = over[]; n′ isa GetNode)
        push!(path, n′.name)
        over = n′.over
    end
    ex = nameof(Get)
    while !isempty(path)
        name = pop!(path)
        ex = Expr(:., ex, quoteof(name))
    end
    if over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(over), ex)
    end
    ex
end

rebase(n::GetNode, n′) =
    GetNode(over = rebase(n.over, n′), name = n.name)

alias(n::GetNode) =
    n.name

function gather!(refs::Vector{SQLNode}, n::GetNode)
    push!(refs, n)
end

translate(n::GetNode, subs) =
    error("unknown name $(n.name)")

