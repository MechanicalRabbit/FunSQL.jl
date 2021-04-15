# Syntactic structure of a SQL query.


# Base type.

"""
A part of a SQL query.
"""
abstract type AbstractSQLClause
end

function dissect(scr::Symbol, ClauseType::Type{<:AbstractSQLClause}, pats::Vector{Any})
    scr_core = gensym(:scr_core)
    ex = Expr(:&&, :($scr_core isa $ClauseType), Any[dissect(scr_core, pat) for pat in pats]...)
    :($scr isa SQLClause && (local $scr_core = $scr[]; $ex))
end


# Opaque wrapper that serves as a specialization barrier.

"""
An opaque wrapper over an arbitrary SQL clause.
"""
struct SQLClause <: AbstractSQLClause
    core::AbstractSQLClause

    SQLClause(@nospecialize core::AbstractSQLClause) =
        new(core)
end

Base.getindex(c::SQLClause) =
    c.core

Base.convert(::Type{SQLClause}, c::SQLClause) =
    c

Base.convert(::Type{SQLClause}, @nospecialize c::AbstractSQLClause) =
    SQLClause(c)

Base.convert(::Type{SQLClause}, obj) =
    convert(SQLClause, convert(AbstractSQLClause, obj)::AbstractSQLClause)

(c::AbstractSQLClause)(c′) =
    c(convert(SQLClause, c′))

(c::AbstractSQLClause)(c′::SQLClause) =
    rebase(c, c′)

rebase(c::SQLClause, c′) =
    convert(SQLClause, rebase(c[], c′))

rebase(::Nothing, c′) =
    c′


# Pretty-printing.

Base.show(io::IO, c::AbstractSQLClause) =
    print(io, quoteof(c, limit = true))

Base.show(io::IO, ::MIME"text/plain", c::AbstractSQLClause) =
    pprint(io, c)

struct SQLClauseQuoteContext
    limit::Bool

    SQLClauseQuoteContext(; limit = false) =
        new(limit)
end

function PrettyPrinting.quoteof(c::SQLClause; limit::Bool = false, unwrap::Bool = false)
    qctx = SQLClauseQuoteContext(limit = limit)
    ex = quoteof(c[], qctx)
    if unwrap
        ex = Expr(:ref, ex)
    end
    ex
end

PrettyPrinting.quoteof(c::AbstractSQLClause; limit::Bool = false) =
    quoteof(convert(SQLClause, c), limit = limit, unwrap = true)

PrettyPrinting.quoteof(c::SQLClause, qctx::SQLClauseQuoteContext) =
    if !qctx.limit
        quoteof(c[], qctx)
    else
        :…
    end

PrettyPrinting.quoteof(cs::Vector{SQLClause}, qctx::SQLClauseQuoteContext) =
    if isempty(cs)
        Any[]
    elseif !qctx.limit
        Any[quoteof(c, qctx) for c in cs]
    else
        Any[:…]
    end


# Concrete clause types.

include("clauses/as.jl")
include("clauses/case.jl")
include("clauses/from.jl")
include("clauses/function.jl")
include("clauses/group.jl")
include("clauses/identifier.jl")
include("clauses/join.jl")
include("clauses/keyword.jl")
include("clauses/literal.jl")
include("clauses/operator.jl")
include("clauses/select.jl")
include("clauses/where.jl")

