# SQL functions.

mutable struct FunctionClause <: AbstractSQLClause
    name::Symbol
    args::Vector{SQLClause}

    FunctionClause(;
                   name::Union{Symbol, AbstractString},
                   args = SQLClause[]) =
        new(Symbol(name), args)
end

FunctionClause(name; args = SQLClause[]) =
    FunctionClause(name = name, args = args)

FunctionClause(name, args...) =
    FunctionClause(name, args = SQLClause[args...])

"""
    FUN(; name, args = [])
    FUN(name; args = [])
    FUN(name, args...)

An invocation of a SQL function.

# Examples

```jldoctest
julia> c = FUN(:EXTRACT, OP(:YEAR), KW(:FROM, FUN(:NOW)));

julia> print(render(c))
EXTRACT(YEAR FROM NOW())
```
"""
FUN(args...; kws...) =
    FunctionClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(FUN), pats::Vector{Any}) =
    dissect(scr, FunctionClause, pats)

PrettyPrinting.quoteof(c::FunctionClause, qctx::SQLClauseQuoteContext) =
    Expr(:call, nameof(FUN), string(c.name), quoteof(c.args, qctx)...)

