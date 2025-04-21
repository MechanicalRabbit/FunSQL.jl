# SQL identifier.

struct IdentifierClause <: AbstractSQLClause
    name::Symbol

    IdentifierClause(; name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

IdentifierClause(name) =
    IdentifierClause(; name)

"""
    ID(; name, tail = nothing)
    ID(name; tail = nothing)
    ID(qualifiers..., name; tail = nothing)

A SQL identifier.  Use the `|>` operator to make a qualified identifier.

# Examples

```jldoctest
julia> s = ID(:person);

julia> print(render(s))
"person"
```

```jldoctest
julia> s = ID(:p) |> ID(:birth_datetime);

julia> print(render(s))
"p"."birth_datetime"
```

```jldoctest
julia> s = ID([:pg_catalog], :pg_database);

julia> print(render(s))
"pg_catalog"."pg_database"
```
"""
const ID = SQLSyntaxCtor{IdentifierClause}

ID(qualifier::Union{Symbol, AbstractString}, name::Union{Symbol, AbstractString}; tail = nothing) =
    ID(tail = ID(qualifier; tail), name = name)

ID(name1::Union{Symbol, AbstractString}, name2::Union{Symbol, AbstractString}, names::Union{Symbol, AbstractString}...; tail = nothing) =
    ID(tail = ID(name1; tail), name2, names...)

function ID(qualifiers::AbstractVector{<:Union{Symbol, AbstractString}}, name::Union{Symbol, AbstractString}; tail = nothing)
    for q in qualifiers
        tail = ID(tail = tail, name = q)
    end
    ID(; tail, name)
end

ID(t::SQLTable) =
    ID(t.qualifiers, t.name)

Base.convert(::Type{SQLSyntax}, name::Symbol) =
    ID(name)

Base.convert(::Type{SQLSyntax}, qname::Tuple{Symbol, Vararg{Symbol}}) =
    ID(qname...)

Base.convert(::Type{SQLSyntax}, qname::Tuple{Vector{Symbol}, Symbol}) =
    ID(qname...)

Base.convert(::Type{SQLSyntax}, t::SQLTable) =
    ID(t)

PrettyPrinting.quoteof(c::IdentifierClause, ctx::QuoteContext) =
    Expr(:call, :ID, quoteof(c.name))
