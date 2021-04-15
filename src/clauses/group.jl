# GROUP BY clause.

mutable struct GroupClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    partition::Vector{SQLClause}

    GroupClause(;
                over = nothing,
                partition = SQLClause[]) =
        new(over, partition)
end

GroupClause(partition...; over = nothing) =
    GroupClause(over = over, partition = SQLClause[partition...])

"""
    GROUP(; over = nothing, partition = [])
    GROUP(partition...; over = nothing)

A `GROUP BY` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           GROUP(:year_of_birth) |>
           SELECT(:year_of_birth, FUN("COUNT", OP("*")));

julia> print(render(c))
SELECT "year_of_birth", COUNT(*)
FROM "person"
GROUP BY "year_of_birth"
```
"""
GROUP(args...; kws...) =
    GroupClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(GROUP), pats::Vector{Any}) =
    dissect(scr, GroupClause, pats)

function PrettyPrinting.quoteof(c::GroupClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(GROUP))
    append!(ex.args, quoteof(c.partition, qctx))
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::GroupClause, c′) =
    GroupClause(over = rebase(c.over, c′), partition = c.partition)

