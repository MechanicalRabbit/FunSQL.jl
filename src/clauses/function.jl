# SQL functions.

struct FunctionClause <: AbstractSQLClause
    name::Symbol
    args::Vector{SQLSyntax}

    FunctionClause(;
                   name::Union{Symbol, AbstractString},
                   args = SQLSyntax[]) =
        new(Symbol(name), args)
end

FunctionClause(name; args = SQLSyntax[]) =
    FunctionClause(; name, args)

FunctionClause(name, args...) =
    FunctionClause(; name, args = SQLSyntax[args...])

"""
    FUN(; name, args = [])
    FUN(name; args = [])
    FUN(name, args...)

An invocation of a SQL function or a SQL operator.

# Examples

```jldoctest
julia> s = FUN(:concat, :city, ", ", :state);

julia> print(render(s))
concat("city", ', ', "state")
```

```jldoctest
julia> s = FUN("||", :city, ", ", :state);

julia> print(render(s))
("city" || ', ' || "state")
```

```jldoctest
julia> s = FUN("SUBSTRING(? FROM ? FOR ?)", :zip, 1, 3);

julia> print(render(s))
SUBSTRING("zip" FROM 1 FOR 3)
```
"""
const FUN = SQLSyntaxCtor{FunctionClause}

Base.convert(::Type{SQLSyntax}, ::typeof(*)) =
    FUN(:*)

PrettyPrinting.quoteof(c::FunctionClause, ctx::QuoteContext) =
    Expr(:call, :FUN, string(c.name), quoteof(c.args, ctx)...)
