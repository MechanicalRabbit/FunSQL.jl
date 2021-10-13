# AS clause.

mutable struct AsClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    name::Symbol

    AsClause(;
             over = nothing,
             name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

AsClause(name; over = nothing) =
    AsClause(over = over, name = name)

"""
    AS(; over = nothing, name)
    AS(name; over = nothing)

An `AS` clause.

# Examples

```jldoctest
julia> c = ID(:person) |> AS(:p);

julia> print(render(c))
"person" AS "p"
```
"""
AS(args...; kws...) =
    AsClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(AS), pats::Vector{Any}) =
    dissect(scr, AsClause, pats)

Base.convert(::Type{AbstractSQLClause}, p::Pair{<:Union{Symbol, AbstractString}}) =
    AsClause(name = first(p), over = convert(SQLClause, last(p)))

function PrettyPrinting.quoteof(c::AsClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(AS), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::AsClause, c′) =
    AsClause(over = rebase(c.over, c′), name = c.name)

