# Window definition clause.

mutable struct PartitionClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    by::Vector{SQLClause}
    order_by::Vector{SQLClause}

    PartitionClause(;
                    over = nothing,
                    by = SQLClause[],
                    order_by = SQLClause[]) =
        new(over, by, order_by)
end

PartitionClause(by...; over = nothing, order_by = SQLClause[]) =
    PartitionClause(over = over, by = SQLClause[by...], order_by = order_by)

"""
    PARTITION(; over = nothing, by = [], order_by = [])
    PARTITION(by...; over = nothing, order_by = [])

A window definition clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           SELECT(:person_id,
                  AGG("ROW_NUMBER", over = PARTITION(:year_of_birth)));

julia> print(render(c))
SELECT "person_id", (ROW_NUMBER() OVER (PARTITION BY "year_of_birth"))
FROM "person"
```

```jldoctest
julia> c = FROM(:person) |>
           WINDOW(:w1 => PARTITION(:year_of_birth),
                  :w2 => :w1 |> PARTITION(order_by = [:month_of_birth, :day_of_birth])) |>
           SELECT(:person_id, AGG("ROW_NUMBER", over = :w2));

julia> print(render(c))
SELECT "person_id", (ROW_NUMBER() OVER ("w2"))
FROM "person"
WINDOW "w1" AS (PARTITION BY "year_of_birth"), "w2" AS ("w1" ORDER BY "month_of_birth", "day_of_birth")
```
"""
PARTITION(args...; kws...) =
    PartitionClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(PARTITION), pats::Vector{Any}) =
    dissect(scr, PartitionClause, pats)

function PrettyPrinting.quoteof(c::PartitionClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(PARTITION))
    append!(ex.args, quoteof(c.by, qctx))
    if !isempty(c.order_by)
        push!(ex.args, Expr(:kw, :order_by, quoteof(c.order_by, qctx)))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::PartitionClause, c′) =
    PartitionClause(over = rebase(c.over, c′), by = c.by, order_by = c.order_by)

