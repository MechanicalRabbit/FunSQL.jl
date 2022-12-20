# Aggregate functions.

mutable struct AggregateClause <: AbstractSQLClause
    name::Symbol
    args::Vector{SQLClause}
    filter::Union{SQLClause, Nothing}
    over::Union{SQLClause, Nothing}

    AggregateClause(;
                    name::Union{Symbol, AbstractString},
                    args = SQLClause[],
                    filter = nothing,
                    over = nothing) =
        new(Symbol(name), args, filter, over)
end

AggregateClause(name; args = SQLClause[], filter = nothing, over = nothing) =
    AggregateClause(name = name, args = args, filter = filter, over = over)

AggregateClause(name, args...; filter = nothing, over = nothing) =
    AggregateClause(name, args = SQLClause[args...], filter = filter, over = over)

"""
    AGG(; name, args = [], filter = nothing, over = nothing)
    AGG(name; args = [], filter = nothing, over = nothing)
    AGG(name, args...; filter = nothing, over = nothing)

An application of an aggregate function.

# Examples

```jldoctest
julia> c = AGG(:max, :year_of_birth);

julia> print(render(c))
max("year_of_birth")
```

```jldoctest
julia> c = AGG(:count, filter = FUN(">", :year_of_birth, 1970));

julia> print(render(c))
(count(*) FILTER (WHERE ("year_of_birth" > 1970)))
```

```jldoctest
julia> c = AGG(:row_number, over = PARTITION(:year_of_birth));

julia> print(render(c))
(row_number() OVER (PARTITION BY "year_of_birth"))
```
"""
AGG(args...; kws...) =
    AggregateClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(AGG), pats::Vector{Any}) =
    dissect(scr, AggregateClause, pats)

function PrettyPrinting.quoteof(c::AggregateClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(AGG), string(c.name))
    append!(ex.args, quoteof(c.args, ctx))
    if c.filter !== nothing
        push!(ex.args, Expr(:kw, :filter, quoteof(c.filter, ctx)))
    end
    if c.over !== nothing
        push!(ex.args, Expr(:kw, :over, quoteof(c.over, ctx)))
    end
    ex
end

rebase(c::AggregateClause, c′) =
    AggregateClause(name = c.name, args = c.args, filter = c.filter, over = rebase(c.over, c′))
