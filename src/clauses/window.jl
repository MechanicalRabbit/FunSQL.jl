# WINDOW clause.

mutable struct WindowClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    args::Vector{SQLClause}

    WindowClause(;
                 over = nothing,
                 args) =
        new(over, args)
end

WindowClause(args...; over = nothing) =
    WindowClause(over = over, args = SQLClause[args...])

"""
    WINDOW(; over = nothing, args)
    WINDOW(args...; over = nothing)

A `WINDOW` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           WINDOW(:w1 => PARTITION(:year_of_birth),
                  :w2 => :w1 |> PARTITION(order_by = [:month_of_birth, :day_of_birth])) |>
           SELECT(:person_id, AGG("ROW_NUMBER", over = :w2));

julia> print(render(c))
SELECT
  "person_id",
  (ROW_NUMBER() OVER ("w2"))
FROM "person"
WINDOW
  "w1" AS (PARTITION BY "year_of_birth"),
  "w2" AS ("w1" ORDER BY "month_of_birth", "day_of_birth")
```
"""
WINDOW(args...; kws...) =
    WindowClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(WINDOW), pats::Vector{Any}) =
    dissect(scr, WindowClause, pats)

function PrettyPrinting.quoteof(c::WindowClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(WINDOW))
    if isempty(c.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.args, ctx))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::WindowClause, c′) =
    WindowClause(over = rebase(c.over, c′), args = c.args)

