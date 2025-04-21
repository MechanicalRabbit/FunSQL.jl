# UNION clause.

struct UnionClause <: AbstractSQLClause
    all::Bool
    args::Vector{SQLSyntax}

    UnionClause(;
               all = false,
               args) =
        new(all, args)
end

UnionClause(args...; all = false) =
    UnionClause(; all, args = SQLSyntax[args...])

"""
    UNION(; all = false, args, tail = nothing)
    UNION(args...; all = false, tail = nothing)

A `UNION` clause.

# Examples

```jldoctest
julia> s = FROM(:measurement) |>
           SELECT(:person_id, :date => :measurement_date) |>
           UNION(all = true,
                 FROM(:observation) |>
                 SELECT(:person_id, :date => :observation_date));

julia> print(render(s))
SELECT
  "person_id",
  "measurement_date" AS "date"
FROM "measurement"
UNION ALL
SELECT
  "person_id",
  "observation_date" AS "date"
FROM "observation"
```
"""
const UNION = SQLSyntaxCtor{UnionClause}

function PrettyPrinting.quoteof(c::UnionClause, ctx::QuoteContext)
    ex = Expr(:call, :UNION)
    if c.all !== false
        push!(ex.args, Expr(:kw, :all, c.all))
    end
    if isempty(c.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.args, ctx))
    end
    ex
end
