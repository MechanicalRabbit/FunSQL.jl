# WINDOW clause.

mutable struct WindowClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    list::Vector{SQLClause}

    WindowClause(;
                 over = nothing,
                 list) =
        new(over, list)
end

WindowClause(list...; over = nothing) =
    WindowClause(over = over, list = SQLClause[list...])

"""
    WINDOW(; over = nothing, list)
    WINDOW(list...; over = nothing)

A `WINDOW` clause.

# Examples

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
WINDOW(args...; kws...) =
    WindowClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(WINDOW), pats::Vector{Any}) =
    dissect(scr, WindowClause, pats)

function PrettyPrinting.quoteof(c::WindowClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(WINDOW))
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

rebase(c::WindowClause, c′) =
    WindowClause(over = rebase(c.over, c′), list = c.list)

