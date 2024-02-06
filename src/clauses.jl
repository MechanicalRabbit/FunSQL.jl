# Syntactic structure of a SQL query.


# Base type.

"""
A component of a SQL syntax tree.
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

Base.:(==)(@nospecialize(::AbstractSQLClause), @nospecialize(::AbstractSQLClause)) =
    false

Base.:(==)(c1::SQLClause, c2::SQLClause) =
    c1[] == c2[]

Base.:(==)(c1::SQLClause, @nospecialize(c2::AbstractSQLClause)) =
    c1[] == c2

Base.:(==)(@nospecialize(c1::AbstractSQLClause), c2::SQLClause) =
    c1 == c2[]

@generated function Base.:(==)(c1::C, c2::C) where {C <: AbstractSQLClause}
    exs = Expr[]
    for f in fieldnames(c1)
        push!(exs, :(isequal(c1.$(f), c2.$(f))))
    end
    Expr(:||, :(c1 === c2), Expr(:&&, exs...))
end

Base.hash(c::SQLClause, h::UInt) =
    hash(c[], h)

@generated function Base.hash(c::AbstractSQLClause, h::UInt)
    ex = :(h + $(hash(c)))
    for f in fieldnames(c)
        ex = :(hash(c.$(f), $ex))
    end
    ex
end


# Pretty-printing.

Base.show(io::IO, c::AbstractSQLClause) =
    print(io, quoteof(c, limit = true))

Base.show(io::IO, ::MIME"text/plain", c::AbstractSQLClause) =
    pprint(io, c)

function PrettyPrinting.quoteof(c::SQLClause; limit::Bool = false, unwrap::Bool = false)
    ctx = QuoteContext(limit = limit)
    ex = quoteof(c[], ctx)
    if unwrap
        ex = Expr(:ref, ex)
    end
    ex
end

PrettyPrinting.quoteof(c::AbstractSQLClause; limit::Bool = false) =
    quoteof(convert(SQLClause, c), limit = limit, unwrap = true)

PrettyPrinting.quoteof(c::SQLClause, ctx::QuoteContext) =
    if !ctx.limit
        quoteof(c[], ctx)
    else
        :…
    end

PrettyPrinting.quoteof(cs::Vector{SQLClause}, ctx::QuoteContext) =
    if isempty(cs)
        Any[]
    elseif !ctx.limit
        Any[quoteof(c, ctx) for c in cs]
    else
        Any[:…]
    end

PrettyPrinting.quoteof(names::Vector{Symbol}, ctx::QuoteContext) =
    if isempty(names)
        Any[]
    elseif !ctx.limit
        Any[QuoteNode(name) for name in names]
    else
        Any[:…]
    end


# Concrete clause types.

include("clauses/aggregate.jl")
include("clauses/as.jl")
include("clauses/from.jl")
include("clauses/function.jl")
include("clauses/group.jl")
include("clauses/having.jl")
include("clauses/identifier.jl")
include("clauses/internal.jl")
include("clauses/join.jl")
include("clauses/limit.jl")
include("clauses/literal.jl")
include("clauses/note.jl")
include("clauses/order.jl")
include("clauses/partition.jl")
include("clauses/select.jl")
include("clauses/sort.jl")
include("clauses/union.jl")
include("clauses/values.jl")
include("clauses/variable.jl")
include("clauses/where.jl")
include("clauses/window.jl")
include("clauses/with.jl")
