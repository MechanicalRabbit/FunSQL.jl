# SQL operators.

mutable struct OperatorClause <: AbstractSQLClause
    name::Symbol
    args::Vector{SQLClause}

    OperatorClause(;
                   name::Union{Symbol, AbstractString},
                   args = SQLClause[]) =
        new(Symbol(name), args)
end

OperatorClause(name; args = SQLClause[]) =
    OperatorClause(name = name, args = args)

OperatorClause(name, args...) =
    OperatorClause(name, args = SQLClause[args...])

"""
    OP(; name, args = [])
    OP(name; args = [])
    OP(name, args...)

An application of a SQL operator.

# Examples

```jldoctest
julia> c = OP("NOT", OP("=", :zip, "60614"));

julia> print(render(c))
(NOT ("zip" = '60614'))
```
"""
OP(args...; kws...) =
    OperatorClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(OP), pats::Vector{Any}) =
    dissect(scr, OperatorClause, pats)

Base.convert(::Type{AbstractSQLClause}, ::typeof(*)) =
    OperatorClause(:*)

PrettyPrinting.quoteof(c::OperatorClause, ctx::QuoteContext) =
    Expr(:call, nameof(OP), string(c.name), quoteof(c.args, ctx)...)

