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

```jldoctest
julia> c = ID(:person) |> AS(:p);

julia> print(render(c))
"person" AS "p"
```
"""
AS(args...; kws...) =
    AsClause(args...; kws...) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, p::Pair{<:Union{Symbol, AbstractString}}) =
    AsClause(name = first(p), over = convert(SQLClause, last(p)))

function PrettyPrinting.quoteof(c::AsClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(AS), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::AsClause, c′) =
    AsClause(over = rebase(c.over, c′), name = c.name)

function render(ctx, c::AsClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
        print(ctx, " AS ")
    end
    render(ctx, c.name)
end

