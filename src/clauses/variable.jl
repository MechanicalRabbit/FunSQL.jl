# SQL placeholder parameter.

struct VariableClause <: AbstractSQLClause
    name::Symbol

    VariableClause(; name::Union{Symbol, AbstractString}) =
        new(Symbol(name))
end

VariableClause(name) =
    VariableClause(name = name)

"""
    VAR(; name)
    VAR(name)

A placeholder in a parameterized query.

# Examples

```jldoctest
julia> s = VAR(:year);

julia> print(render(s))
:year
```
"""
const VAR = SQLSyntaxCtor{VariableClause}

terminal(::Type{VariableClause}) =
    true

PrettyPrinting.quoteof(c::VariableClause, ctx::QuoteContext) =
    Expr(:call, :VAR, quoteof(c.name))
