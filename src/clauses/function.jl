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

An invocation of a SQL function or a SQL operator.

# Examples

```jldoctest
julia> c = FUN(:concat, :city, ", ", :state);

julia> print(render(c))
concat("city", ', ', "state")
```

```jldoctest
julia> c = FUN("||", :city, ", ", :state);

julia> print(render(c))
("city" || ', ' || "state")
```

```jldoctest
julia> c = FUN("SUBSTRING(? FROM ? FOR ?)", :zip, 1, 3);

julia> print(render(c))
SUBSTRING("zip" FROM 1 FOR 3)
```
"""
FUN(args...; kws...) =
    FunctionClause(args...; kws...) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, ::typeof(*)) =
    FunctionClause(:*)

dissect(scr::Symbol, ::typeof(FUN), pats::Vector{Any}) =
    dissect(scr, FunctionClause, pats)

PrettyPrinting.quoteof(c::FunctionClause, ctx::QuoteContext) =
    Expr(:call, nameof(FUN), string(c.name), quoteof(c.args, ctx)...)
