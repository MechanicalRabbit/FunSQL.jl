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

function dissect(scr::Symbol, ClauseType::Type{<:AbstractSQLClause}, pats::Vector{Any})
    scr_core = gensym(:scr_core)
    ex = Expr(:&&, :($scr_core isa $ClauseType), Any[dissect(scr_core, pat) for pat in pats]...)
    :($scr isa SQLClause && (local $scr_core = $scr[]; $ex))
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


# Collapsing nodes.

collapse(c::AbstractSQLClause) =
    c

collapse(c::SQLClause) =
    collapse(c[]) |> SQLClause

collapse(cs::Vector{SQLClause}) =
    SQLClause[collapse(c) for c in cs]

function substitutions(alias::Symbol, cs::Vector{SQLClause})
    subs = Dict{Tuple{Symbol, Symbol}, SQLClause}()
    for c in cs
        if @dissect c AS(over = repl, name = name)
        elseif @dissect c ID(name = name)
            repl = c
        else
            continue
        end
        subs[(alias, name)] = repl
    end
    subs
end

collapse(::Nothing) =
    nothing

collapse(c::AsClause) =
    AsClause(over = collapse(c.over), name = c.name)

collapse(c::FromClause) =
    FromClause(over = collapse(c.over))

function collapse(c::SelectClause)
    list = collapse(c.list)
    c = SelectClause(over = collapse(c.over), distinct = c.distinct, list = unalias(list))
    @dissect(c.over, select_over |>
                     SELECT(distinct = false, list = select_list) |>
                     AS(name = alias) |>
                     FROM()) || return c
    subs = substitutions(alias, select_list)
    subs !== nothing || return c
    list′ = substitute(list, subs)
    SelectClause(over = select_over, distinct = c.distinct, list = unalias(list′))
end

function collapse(c::WhereClause)
    c = WhereClause(over = collapse(c.over), condition = collapse(c.condition))
    @dissect(c.over, (tail := nothing || FROM() || WHERE()) |>
                     SELECT(distinct = false, list = select_list) |>
                     AS(name = alias) |>
                     FROM()) || return c
    subs = substitutions(alias, select_list)
    subs !== nothing || return c
    condition′ = substitute(c.condition, subs)
    if @dissect tail (tail |> WHERE(condition = tail_condition))
        if @dissect tail_condition OP(name = :AND, args = args)
            condition′ = OP(:AND, args..., condition′)
        else
            condition′ = OP(:AND, tail_condition, condition′)
        end
    end
    c′ = WHERE(over = tail, condition = condition′)
    c′ = SELECT(over = c′, list = select_list)
    c′ = AS(over = c′, name = alias)
    FromClause(over = c′)
end

unalias(cs::Vector{SQLClause}) =
    SQLClause[unalias(c) for c in cs]

function unalias(c::SQLClause)
    if @dissect c (tail := ID(name = id_name)) |> AS(name = as_name)
        if id_name === as_name
            return tail
        end
    end
    c
end

function substitute(c::SQLClause, subs::Dict{Tuple{Symbol, Symbol}, SQLClause})
    if @dissect c nothing |> ID(name = base_name) |> ID(name = name)
        key = (base_name, name)
        if key in keys(subs)
            return subs[key]
        end
    end
    substitute(c[], subs)
end

substitute(cs::Vector{SQLClause}, subs::Dict{Tuple{Symbol, Symbol}, SQLClause}) =
    SQLClause[substitute(c, subs) for c in cs]

substitute(::Nothing, subs::Dict{Tuple{Symbol, Symbol}, SQLClause}) =
    nothing

@generated function substitute(c::AbstractSQLClause, subs::Dict{Tuple{Symbol, Symbol}, SQLClause})
    exs = Expr[]
    args = Expr[]
    fs = fieldnames(c)
    for f in fs
        t = fieldtype(c, f)
        if t === SQLClause || t === Union{SQLClause, Nothing} || t === Vector{SQLClause}
            ex = quote
                $(f) = substitute(c.$(f), subs)
            end
            push!(exs, ex)
            arg = Expr(:kw, f, f)
            push!(args, arg)
        else
            arg = :(c.$(f))
            push!(args, arg)
        end
    end
    if isempty(exs)
        return :(return c)
    end
    push!(exs, :($c($(args...))))
    Expr(:block, exs...)
end

