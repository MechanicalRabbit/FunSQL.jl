# Syntactic structure of a SQL query.


# Rendering SQL.

mutable struct RenderContext <: IO
    dialect::SQLDialect
    io::IOBuffer
    level::Int
    nested::Bool

    RenderContext(dialect) =
        new(dialect, IOBuffer(), 0, false)
end

Base.write(ctx::RenderContext, octet::UInt8) =
    write(ctx.io, octet)

Base.unsafe_write(ctx::RenderContext, input::Ptr{UInt8}, nbytes::UInt) =
    unsafe_write(ctx.io, input, nbytes)

function newline(ctx::RenderContext)
    print(ctx, "\n")
    for k = 1:ctx.level
        print(ctx, "  ")
    end
end


# Base type.

"""
A part of a SQL query.
"""
abstract type AbstractSQLClause
end

function render(c::AbstractSQLClause; dialect = :default)
    ctx = RenderContext(dialect)
    render(ctx, convert(SQLClause, c))
    String(take!(ctx.io))
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

PrettyPrinting.quoteof(c::AbstractSQLClause; limit::Bool = false) =
    quoteof(SQLClause(c), limit = limit, unwrap = true)

function PrettyPrinting.quoteof(c::SQLClause; limit::Bool = false, unwrap::Bool = false)
    qctx = SQLClauseQuoteContext(limit = limit)
    ex = quoteof(c[], qctx)
    if unwrap
        ex = Expr(:ref, ex)
    end
    ex
end

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


# Rendering SQL.

render(ctx, c::SQLClause) =
    render(ctx, c[])

function render(ctx, cs::AbstractVector{SQLClause}; sep = ", ", left = "(", right = ")")
    print(ctx, left)
    first = true
    for c in cs
        if !first
            print(ctx, sep)
        else
            first = false
        end
        render(ctx, c)
    end
    print(ctx, right)
end


# Concrete clause types.

include("clauses/as.jl")
include("clauses/from.jl")
include("clauses/identifier.jl")
include("clauses/literal.jl")
include("clauses/operator.jl")
include("clauses/select.jl")
include("clauses/where.jl")

