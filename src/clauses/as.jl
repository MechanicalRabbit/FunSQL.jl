# AS clause.

mutable struct AsClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    name::Symbol
    columns::Union{Vector{Symbol}, Nothing}

    AsClause(;
             over = nothing,
             name::Union{Symbol, AbstractString},
             columns::Union{AbstractVector{<:Union{Symbol, AbstractString}}, Nothing} = nothing) =
        new(over,
            Symbol(name),
            !(columns === nothing || columns isa Vector{Symbol}) ?
                Symbol[Symbol(col) for col in columns] : columns)
end

AsClause(name; over = nothing, columns = nothing) =
    AsClause(over = over, name = name, columns = columns)

"""
    AS(; over = nothing, name, columns = nothing)
    AS(name; over = nothing, columns = nothing)

An `AS` clause.

# Examples

```jldoctest
julia> c = ID(:person) |> AS(:p);

julia> print(render(c))
"person" AS "p"
```

```jldoctest
julia> c = ID(:person) |> AS(:p, columns = [:person_id, :year_of_birth]);

julia> print(render(c))
"person" AS "p" ("person_id", "year_of_birth")
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
    if c.columns !== nothing
        push!(ex.args, Expr(:kw, :columns, Expr(:vect, quoteof(c.columns, ctx)...)))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::AsClause, c′) =
    AsClause(over = rebase(c.over, c′), name = c.name, columns = c.columns)

