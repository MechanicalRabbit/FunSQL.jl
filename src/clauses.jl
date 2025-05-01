# Syntactic structure of a SQL query.


# Base abstract type of a node in a SQL syntax tree.

"""
A component of a SQL syntax tree.
"""
abstract type AbstractSQLClause
end

terminal(::Type{<:AbstractSQLClause}) =
    false

terminal(c::C) where {C <: AbstractSQLClause} =
    terminal(C)


# Opaque linked list of SQL clauses.

"""
SQL syntax tree represented as a linked list of SQL clauses.
"""
struct SQLSyntax
    tail::Union{SQLSyntax, Nothing}
    head::AbstractSQLClause

    SQLSyntax(@nospecialize head::AbstractSQLClause) =
        new(nothing, head)

    function SQLSyntax(tail, head::AbstractSQLClause)
        if tail !== nothing && terminal(head)
            throw(RebaseError(path = [SQLSyntax(head)]))
        end
        new(tail, head)
    end
end

Base.convert(::Type{SQLSyntax}, @nospecialize c::AbstractSQLClause) =
    SQLSyntax(c)

terminal(s::SQLSyntax) =
    s.tail !== nothing ? terminal(s.tail) : terminal(s.head)

(s::SQLSyntax)(s′) =
    SQLSyntax(s.tail !== nothing ? s.tail(s′) : s′, s.head)

Base.:(==)(@nospecialize(::AbstractSQLClause), @nospecialize(::AbstractSQLClause)) =
    false

Base.:(==)(s1::SQLSyntax, s2::SQLSyntax) =
    s1 === s2 || s1.head == s2.head && s1.tail == s2.tail

@generated function Base.:(==)(c1::C, c2::C) where {C <: AbstractSQLClause}
    exs = Expr[]
    for f in fieldnames(c1)
        push!(exs, :(isequal(c1.$(f), c2.$(f))))
    end
    Expr(:||, :(c1 === c2), Expr(:&&, exs...))
end

Base.hash(s::SQLSyntax, h::UInt) =
    s.tail !== nothing ? hash(s.tail, hash(s.head, h)) : hash(s.head, h)

@generated function Base.hash(c::AbstractSQLClause, h::UInt)
    ex = :(h + $(hash(c)))
    for f in fieldnames(c)
        ex = :(hash(c.$(f), $ex))
    end
    ex
end


# Pretty-printing.

Base.show(io::IO, c::Union{AbstractSQLClause, SQLSyntax}) =
    print(io, quoteof(c, limit = true))

Base.show(io::IO, ::MIME"text/plain", c::Union{AbstractSQLClause, SQLSyntax}) =
    pprint(io, c)

function PrettyPrinting.quoteof(s::SQLSyntax; limit::Bool = false, head_only::Bool = false)
    ctx = QuoteContext(limit = limit)
    ex = quoteof(s, ctx)
    if head_only
        ex = Expr(:., ex, QuoteNode(:head))
    end
    ex
end

PrettyPrinting.quoteof(c::AbstractSQLClause; limit::Bool = false) =
    quoteof(convert(SQLSyntax, c), limit = limit, head_only = true)

function PrettyPrinting.quoteof(s::SQLSyntax, ctx::QuoteContext)
    ex = quoteof(s.head, ctx)
    if s.tail !== nothing
        ex = Expr(:call, :|>, !ctx.limit ? quoteof(s.tail, ctx) : :…, ex)
    end
    ex
end

PrettyPrinting.quoteof(ss::Vector{SQLSyntax}, ctx::QuoteContext) =
    if isempty(ss)
        Any[]
    elseif !ctx.limit
        Any[quoteof(s, ctx) for s in ss]
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


# Support for clause constructors.

struct SQLSyntaxCtor{C<:AbstractSQLClause}
    id::Symbol
end

Base.show(io::IO, @nospecialize ctor::SQLSyntaxCtor{C}) where {C} =
    print(io, ctor.id)

(::SQLSyntaxCtor{C})(args...; tail = nothing, kws...) where {C} =
    SQLSyntax(tail, C(args...; kws...))

function dissect(scr::Symbol, ::SQLSyntaxCtor{C}, pats::Vector{Any}) where {C<:AbstractSQLClause}
    head_pats = Any[]
    tail_pats = Any[]
    for pat in pats
        if pat isa Expr && pat.head === :kw && length(pat.args) == 2 && pat.args[1] === :tail
            push!(tail_pats, pat.args[2])
        else
            push!(head_pats, pat)
        end
    end
    scr_head = gensym(:scr_head)
    head_ex = Expr(:&&, :($scr_head isa $C), Any[dissect(scr_head, pat) for pat in head_pats]...)
    ex = Expr(:&&, :($scr isa SQLSyntax), :(local $scr_head = $scr.head; $head_ex))
    if !isempty(tail_pats)
        scr_tail = gensym(:scr_tail)
        tail_ex = Expr(:&&, Any[dissect(scr_tail, pat) for pat in tail_pats]...)
        push!(ex.args, :(local $scr_tail = $scr.tail; $tail_ex))
    end
    ex
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
