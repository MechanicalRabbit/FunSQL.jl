# SQL placeholder parameter.

mutable struct VariableClause <: AbstractSQLClause
    name::Symbol

    VariableClause(; name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

VariableClause(name) =
    VariableClause(name = name)

"""
    VAR(; name)
    VAR(name)

A placeholder parameter in a prepared statement.

# Examples

```jldoctest
julia> c = VAR(:year);

julia> print(render(c))
:year
```
"""
VAR(args...; kws...) =
    VariableClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(VAR), pats::Vector{Any}) =
    dissect(scr, VariableClause, pats)

PrettyPrinting.quoteof(c::VariableClause, qctx::SQLClauseQuoteContext) =
    Expr(:call, nameof(VAR), quoteof(c.name))

