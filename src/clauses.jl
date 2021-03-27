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


# Opaque wrapper that serves as a specialization barrier.

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


# Concrete clause types.

include("clauses/literal.jl")
include("clauses/identifier.jl")
include("clauses/as.jl")
include("clauses/from.jl")
include("clauses/select.jl")
include("clauses/where.jl")

