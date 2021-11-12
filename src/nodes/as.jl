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

In a scalar context, `As` specifies the name of the output column.  When
applied to a tabular node, `As` wraps the output of the node in a nested
record.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           As(:p) |>
           Select(:birth_year => Get.p.year_of_birth);
```
"""
As(args...; kws...) =
    AsNode(args...; kws...) |> SQLNode

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

rebase(n::AsNode, n′) =
    AsNode(over = rebase(n.over, n′), name = n.name)

