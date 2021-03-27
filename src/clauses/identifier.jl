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

```julia-repl
julia> c = ID(:person);

julia> print(render(c))
"person"
```

```julia-repl
julia> c = ID(:p) |> ID(:birth_datetime);

julia> print(render(c))
"p"."birth_datetime"
```
"""
ID(args...; kws...) =
    IdentifierClause(args...; kws...) |> SQLClause

Base.convert(::Type{AbstractSQLClause}, name::Symbol) =
    IdentifierClause(name)

Base.convert(::Type{AbstractSQLClause}, qname::Tuple{Symbol, Symbol}) =
    IdentifierClause(qname[2], over = IdentifierClause(qname[1]))

function PrettyPrinting.quoteof(c::IdentifierClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call, wrap ? nameof(ID) : nameof(IdentifierClause), quoteof(c.name))
    if c.over !== nothing
        ex = Expr(:call, :|>, limit ? :… : quoteof(c.over), ex)
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

