# AS clause.

mutable struct AsClause <: AbstractSQLClause
    name::Symbol
    columns::Union{Vector{Symbol}, Nothing}

    AsClause(;
             name::Union{Symbol, AbstractString},
             columns::Union{AbstractVector{<:Union{Symbol, AbstractString}}, Nothing} = nothing) =
        new(Symbol(name),
            !(columns === nothing || columns isa Vector{Symbol}) ?
                Symbol[Symbol(col) for col in columns] : columns)
end

AsClause(name; columns = nothing) =
    AsClause(; name, columns)

"""
    AS(; name, columns = nothing, tail = nothing)
    AS(name; columns = nothing, tail = nothing)

An `AS` clause.

# Examples

```jldoctest
julia> s = ID(:person) |> AS(:p);

julia> print(render(s))
"person" AS "p"
```

```jldoctest
julia> s = ID(:person) |> AS(:p, columns = [:person_id, :year_of_birth]);

julia> print(render(s))
"person" AS "p" ("person_id", "year_of_birth")
```
"""
const AS = SQLSyntaxCtor{AsClause}

Base.convert(::Type{SQLSyntax}, p::Pair{Symbol}) =
    SQLSyntax(last(p), AsClause(name = first(p)))

function PrettyPrinting.quoteof(c::AsClause, ctx::QuoteContext)
    ex = Expr(:call, :AS, quoteof(c.name))
    if c.columns !== nothing
        push!(ex.args, Expr(:kw, :columns, Expr(:vect, quoteof(c.columns, ctx)...)))
    end
    ex
end
