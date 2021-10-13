# UNION clause.

mutable struct UnionClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    all::Bool
    list::Vector{SQLClause}

    UnionClause(;
               over = nothing,
               all = false,
               list) =
        new(over, all, list)
end

UnionClause(list...; over = nothing, all = false) =
    UnionClause(over = over, all = all, list = SQLClause[list...])

"""
    UNION(; over = nothing, all = false, list)
    UNION(list...; over = nothing, all = false)

A `UNION` clause.

# Examples

```jldoctest
julia> c = FROM(:measurement) |>
           SELECT(:person_id, :date => :measurement_date) |>
           UNION(all = true,
                 FROM(:observation) |>
                 SELECT(:person_id, :date => :observation_date));

julia> print(render(c))
SELECT "person_id", "measurement_date" AS "date"
FROM "measurement"
UNION ALL
SELECT "person_id", "observation_date" AS "date"
FROM "observation"
```
"""
UNION(args...; kws...) =
    UnionClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(UNION), pats::Vector{Any}) =
    dissect(scr, UnionClause, pats)

function PrettyPrinting.quoteof(c::UnionClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(UNION))
    if c.all !== false
        push!(ex.args, Expr(:kw, :all, c.all))
    end
    if isempty(c.list)
        push!(ex.args, Expr(:kw, :list, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.list, ctx))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::UnionClause, c′) =
    UnionClause(over = rebase(c.over, c′), list = c.list, all = c.all)

