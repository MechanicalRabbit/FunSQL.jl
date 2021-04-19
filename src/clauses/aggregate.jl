# Aggregate functions.

mutable struct AggregateClause <: AbstractSQLClause
    name::Symbol
    distinct::Bool
    args::Vector{SQLClause}
    filter::Union{SQLClause, Nothing}
    over::Union{SQLClause, Nothing}

    AggregateClause(;
                    name::Union{Symbol, AbstractString},
                    distinct = false,
                    args = SQLClause[],
                    filter = nothing,
                    over = nothing) =
        new(Symbol(name), distinct, args, filter, over)
end

AggregateClause(name; distinct = false, args = SQLClause[], filter = nothing, over = nothing) =
    AggregateClause(name = name, distinct = distinct, args = args, filter = filter, over = over)

AggregateClause(name, args...; distinct = false, filter = nothing, over = nothing) =
    AggregateClause(name, distinct = distinct, args = SQLClause[args...], filter = filter, over = over)

"""
    AGG(; name, distinct = false, args = [], filter = nothing, over = nothing)
    AGG(name; distinct = false, args = [], filter = nothing, over = nothing)
    AGG(name, args...; distinct = false, filter = nothing, over = nothing)

An application of an aggregate function.

# Examples

```jldoctest
julia> c = AGG(:COUNT, OP("*"));

julia> print(render(c))
COUNT(*)
```

```jldoctest
julia> c = AGG(:COUNT, distinct = true, :year_of_birth);

julia> print(render(c))
COUNT(DISTINCT "year_of_birth")
```

```jldoctest
julia> c = AGG(:COUNT, OP("*"), filter = OP(">", :year_of_birth, 1970));

julia> print(render(c))
(COUNT(*) FILTER (WHERE ("year_of_birth" > 1970)))
```

```jldoctest
julia> c = AGG(:ROW_NUMBER, over = PARTITION(:year_of_birth));

julia> print(render(c))
(ROW_NUMBER() OVER (PARTITION BY "year_of_birth"))
```
"""
AGG(args...; kws...) =
    AggregateClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(AGG), pats::Vector{Any}) =
    dissect(scr, AggregateClause, pats)

function PrettyPrinting.quoteof(c::AggregateClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(AGG), string(c.name))
    if c.distinct
        push!(ex.args, Expr(:kw, :distinct, c.distinct))
    end
    append!(ex.args, quoteof(c.args, qctx))
    if c.filter !== nothing
        push!(ex.args, Expr(:kw, :filter, quoteof(c.filter, qctx)))
    end
    ex
end

