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

A SQL identifier.  Specify `over` or use the `|>` operator to make a qualified
identifier.

# Examples

```jldoctest
julia> c = ID(:person);

julia> print(render(c))
"person"
```

```jldoctest
julia> c = ID(:p) |> ID(:birth_datetime);

julia> print(render(c))
"p"."birth_datetime"
```
"""
ID(args...; kws...) =
    IdentifierClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(ID), pats::Vector{Any}) =
    dissect(scr, IdentifierClause, pats)

Base.convert(::Type{AbstractSQLClause}, name::Symbol) =
    IdentifierClause(name)

Base.convert(::Type{AbstractSQLClause}, qname::Tuple{Symbol, Symbol}) =
    IdentifierClause(qname[2], over = IdentifierClause(qname[1]))

function PrettyPrinting.quoteof(c::IdentifierClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(ID), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::IdentifierClause, c′) =
    IdentifierClause(over = rebase(c.over, c′), name = c.name)

function render(ctx, c::IdentifierClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
        print(ctx, '.')
    end
    render(ctx, c.name)
end

render(ctx, name::Symbol) =
    print(ctx, '"', replace(string(name), '"' => "\"\""), '"')

