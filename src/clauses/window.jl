# WINDOW clause.

struct WindowClause <: AbstractSQLClause
    args::Vector{SQLSyntax}

    WindowClause(; args) =
        new(args)
end

WindowClause(args...) =
    WindowClause(args = SQLSyntax[args...])

"""
    WINDOW(; args, tail = nothing)
    WINDOW(args...; tail = nothing)

A `WINDOW` clause.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           WINDOW(:w1 => PARTITION(:year_of_birth),
                  :w2 => :w1 |> PARTITION(order_by = [:month_of_birth, :day_of_birth])) |>
           SELECT(:person_id, AGG("row_number", over = :w2));

julia> print(render(s))
SELECT
  "person_id",
  (row_number() OVER ("w2"))
FROM "person"
WINDOW
  "w1" AS (PARTITION BY "year_of_birth"),
  "w2" AS ("w1" ORDER BY "month_of_birth", "day_of_birth")
```
"""
const WINDOW = SQLSyntaxCtor{WindowClause}

function PrettyPrinting.quoteof(c::WindowClause, ctx::QuoteContext)
    ex = Expr(:call, :WINDOW)
    if isempty(c.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.args, ctx))
    end
    ex
end
