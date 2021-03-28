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

As(args...; kws...) =
    AsNode(args...; kws...) |> SQLNode

Base.convert(::Type{AbstractSQLNode}, p::Pair{<:Union{Symbol, AbstractString}}) =
    AsNode(name = first(p), over = convert(SQLNode, last(p)))

function PrettyPrinting.quoteof(n::AsNode; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(As) : nameof(AsNode), quoteof(n.name))
    if n.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(n.over), ex)
    end
    ex
end

rebase(n::AsNode, n′) =
    AsNode(over = rebase(n.over, n′), name = n.name)


