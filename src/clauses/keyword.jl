# A keyword argument of a function or an operator.

mutable struct KeywordClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    name::Symbol

    KeywordClause(;
             over = nothing,
             name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

KeywordClause(name; over = nothing) =
    KeywordClause(over = over, name = name)

KeywordClause(name, over) =
    KeywordClause(over = over, name = name)

"""
    KW(; over = nothing, name)
    KW(name; over = nothing)
    KW(over, name)

A keyword argument of a function or an operator.

# Examples

```jldoctest
julia> c = FUN(:SUBSTRING, :zip, KW(:FROM, 1), KW(:FOR, 3));

julia> print(render(c))
SUBSTRING("zip" FROM 1 FOR 3)
```

```jldoctest
julia> c = OP(:BETWEEN, :year_of_birth, 2000, KW(:AND, 2010));

julia> print(render(c))
("year_of_birth" BETWEEN 2000 AND 2010)
```
"""
KW(args...; kws...) =
    KeywordClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(KW), pats::Vector{Any}) =
    dissect(scr, KeywordClause, pats)

function PrettyPrinting.quoteof(c::KeywordClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(KW), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::KeywordClause, c′) =
    KeywordClause(over = rebase(c.over, c′), name = c.name)

