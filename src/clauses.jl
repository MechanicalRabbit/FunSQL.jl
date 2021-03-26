# Syntactic structure of a SQL query.

using Dates
using PrettyPrinting: PrettyPrinting, pprint, quoteof


# Base type.

"""
A part of a SQL query.
"""
abstract type AbstractSQLClause
end

Base.show(io::IO, c::AbstractSQLClause) =
    print(io, quoteof(c, limit = true))

Base.show(io::IO, ::MIME"text/plain", c::AbstractSQLClause) =
    pprint(io, c)


# Opaque wrapper.

"""
An opaque wrapper over an arbitrary SQL clause.
"""
struct SQLClause <: AbstractSQLClause
    content::AbstractSQLClause

    SQLClause(@nospecialize content::AbstractSQLClause) =
        new(content)
end

Base.getindex(c::SQLClause) =
    c.content

Base.convert(::Type{SQLClause}, c::SQLClause) =
    c

Base.convert(::Type{SQLClause}, @nospecialize c::AbstractSQLClause) =
    SQLClause(c)

Base.convert(::Type{SQLClause}, obj) =
    convert(SQLClause, convert(AbstractSQLClause, obj)::AbstractSQLClause)

PrettyPrinting.quoteof(c::SQLClause; limit::Bool = false, wrap::Bool = false) =
    quoteof(c.content, limit = limit, wrap = true)

(c::AbstractSQLClause)(c′) =
    c(convert(SQLClause, c′))

(c::AbstractSQLClause)(c′::SQLClause) =
    rebase(c, c′)

rebase(c::SQLClause, c′) =
    convert(SQLClause, rebase(c.content, c′))

rebase(::Nothing, c′) =
    convert(SQLClause, c′)


# Literal value.

const SQLLiteralType =
    Union{Missing, Bool, Number, AbstractString, Dates.AbstractTime}

mutable struct LiteralClause <: AbstractSQLClause
    val
end

"""
    LITERAL(val)

A SQL literal.

# Examples

```julia-repl
julia> c = LITERAL(missing);

julia> print(render(c))
NULL
```

```julia-repl
julia> c = LITERAL(true);

julia> print(render(c))
TRUE
```

```julia-repl
julia> c = LITERAL("SQL is fun!");

julia> print(render(c))
'SQL is fun!'
```
"""
LITERAL(val) =
    LiteralClause(val) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, val::SQLLiteralType) =
    LiteralClause(val)

PrettyPrinting.quoteof(c::LiteralClause; limit::Bool = false, wrap::Bool = false) =
    wrap && c.val isa SQLLiteralType ?
        c.val :
        Expr(:call, wrap ? nameof(LITERAL) : nameof(LiteralClause), c.val)


# SQL identifier (possibly qualified).

mutable struct IdentifierClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    name::Symbol

    IdentifierClause(;
                     over = nothing,
                     name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

IdentifierClause(name; over = nothing) =
    IdentifierClause(over = over, name = name)

"""
    ID(; over = nothing, name)
    ID(name; over = nothing)

A SQL identifier.  Specify `over` to make a qualified identifier.

# Examples

```julia-repl
julia> c = ID(:person);

julia> print(render(c))
"person"
```

```julia-repl
julia> c = ID(:p) |> ID(:birth_datetime);

julia> print(render(c))
"p"."birth_datetime"
```

```julia-repl
julia> c = ID(over = ID("p"), name = "birth_datetime");

julia> print(render(c))
"p"."birth_datetime"
```
"""
ID(args...; kws...) =
    IdentifierClause(args...; kws...) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, name::Symbol) =
    IdentifierClause(name)

Base.convert(::Type{AbstractSQLClause}, qname::Tuple{Symbol, Symbol}) =
    IdentifierClause(qname[2], over = IdentifierClause(qname[1]))

function PrettyPrinting.quoteof(c::IdentifierClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(ID) : nameof(IdentifierClause), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::IdentifierClause, c′) =
    IdentifierClause(over = rebase(c.over, c′), name = c.name)


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

```julia-repl
julia> c = ID(:person) |> AS(:p);

julia> print(render(c))
"person" AS "p"
```

```julia-repl
julia> c = AS(over = ID("person"), name = "p");

julia> print(render(c))
"person" AS "p"
```
"""
AS(args...; kws...) =
    AsClause(args...; kws...) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, p::Pair{<:Union{Symbol, AbstractString}}) =
    AsClause(name = first(p), over = convert(SQLClause, last(p)))

function PrettyPrinting.quoteof(c::AsClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(AS) : nameof(AsClause), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::AsClause, c′) =
    AsClause(over = rebase(c.over, c′), name = c.name)


# FROM clause.

mutable struct FromClause <: AbstractSQLClause
    over::SQLClause

    FromClause(; over = nothing) =
        new(over)
end

FromClause(over) =
    FromClause(over = over)

"""
    FROM(; over = nothing)
    FROM(over)

A `FROM` clause.

# Examples

```julia-repl
julia> c = ID(:person) |> AS(:p) |> FROM();

julia> print(render(c))
FROM "person" AS "p"
```

```julia-repl
julia> c = FROM(ID(:person) |> AS(:p));

julia> print(render(c))
FROM "person" AS "p"
```

```julia-repl
julia> c = FROM(over = ID(:person) |> AS(:p));

julia> print(render(c))
FROM "person" AS "p"
```
"""
FROM(args...; kws...) =
    FromClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::FromClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(FROM) : nameof(FromClause))
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::FromClause, c′) =
    FromClause(over = rebase(c.over, c′))


# SELECT clause.

mutable struct SelectClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    distinct::Union{Bool, Vector{SQLClause}}
    list::Vector{SQLClause}

    SelectClause(;
                 over = nothing,
                 distinct::Union{Bool, AbstractVector} = false,
                 list::AbstractVector) =
        new(over,
            !isa(distinct, Union{Bool, Vector{SQLClause}}) ?
                SQLClause[item for item in distinct] : distinct,
            !isa(list, Vector{SQLClause}) ?
                SQLClause[item for item in list] : list)
end

SelectClause(list...; over = nothing, distinct = false) =
    SelectClause(over = over, distinct = distinct, list = SQLClause[list...])

"""
    SELECT(; over = nothing, distinct = false, list)
    SELECT(list...; over = nothing, distinct = false)

A `SELECT` clause.

Set `distinct` to `true` to add a `DISTINCT` modifier, or provide a vector to
add a `DISTINCT ON` subclause.

# Examples

```julia-repl
julia> c = SELECT(true);

julia> print(render(c))
SELECT TRUE
```

```julia-repl
julia> c = FROM(ID(:person)) |>
           SELECT(ID(:person_id), ID(:birth_datetime));

julia> print(render(c))
SELECT person_id, birth_datetime
FROM person
```

```julia-repl
julia> c = SELECT(over = FROM(ID(:person)),
                  list = [ID(:person_id), ID(:birth_datetime)]);

julia> print(render(c))
SELECT person_id, birth_datetime
FROM person
```

```julia-repl
julia> c = FROM(:location) |>
           SELECT(distinct = true, ID(:zip));

julia> print(render(c))
SELECT DISTINCT zip
FROM location
```
"""
SELECT(args...; kws...) =
    SelectClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::SelectClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(SELECT) : nameof(SelectClause))
    if !limit
        if c.distinct !== false
            distinct_ex =
                c.distinct !== true ?
                Expr(:vect, Any[quoteof(item) for item in c.distinct]...) :
                c.distinct
            push!(ex.args, Expr(:kw, :distinct, distinct_ex))
        end
        list_exs = Any[quoteof(item) for item in c.list]
        if isempty(c.list)
            push!(ex.args, Expr(:kw, :list, Expr(:vect, list_exs...)))
        else
            append!(ex.args, list_exs)
        end
    else
        push!(ex.args, :…)
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
    end
    ex
end

rebase(c::SelectClause, c′) =
    SelectClause(over = rebase(c.over, c′), distinct = c.distinct, list = c.list)
