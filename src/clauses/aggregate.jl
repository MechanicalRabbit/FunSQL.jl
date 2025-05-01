# Aggregate functions.

struct AggregateClause <: AbstractSQLClause
    name::Symbol
    args::Vector{SQLSyntax}
    filter::Union{SQLSyntax, Nothing}
    over::Union{SQLSyntax, Nothing}

    AggregateClause(;
                    name::Union{Symbol, AbstractString},
                    args = SQLSyntax[],
                    filter = nothing,
                    over = nothing) =
        new(Symbol(name), args, filter, over)
end

AggregateClause(name; args = SQLSyntax[], filter = nothing, over = nothing) =
    AggregateClause(; name, args, filter, over)

AggregateClause(name, args...; filter = nothing, over = nothing) =
    AggregateClause(; name, args = SQLSyntax[args...], filter, over)

"""
    AGG(; name, args = [], filter = nothing, over = nothing)
    AGG(name; args = [], filter = nothing, over = nothing)
    AGG(name, args...; filter = nothing, over = nothing)

An application of an aggregate function.

# Examples

```jldoctest
julia> s = AGG(:max, :year_of_birth);

julia> print(render(s))
max("year_of_birth")
```

```jldoctest
julia> s = AGG(:count, filter = FUN(">", :year_of_birth, 1970));

julia> print(render(s))
(count(*) FILTER (WHERE ("year_of_birth" > 1970)))
```

```jldoctest
julia> s = AGG(:row_number, over = PARTITION(:year_of_birth));

julia> print(render(s))
(row_number() OVER (PARTITION BY "year_of_birth"))
```
"""
const AGG = SQLSyntaxCtor{AggregateClause}(:AGG)

function PrettyPrinting.quoteof(c::AggregateClause, ctx::QuoteContext)
    ex = Expr(:call, :AGG, string(c.name))
    append!(ex.args, quoteof(c.args, ctx))
    if c.filter !== nothing
        push!(ex.args, Expr(:kw, :filter, quoteof(c.filter, ctx)))
    end
    if c.over !== nothing
        push!(ex.args, Expr(:kw, :over, quoteof(c.over, ctx)))
    end
    ex
end
