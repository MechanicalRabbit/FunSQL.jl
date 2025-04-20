# JOIN clause.

mutable struct JoinClause <: AbstractSQLClause
    joinee::SQLSyntax
    on::SQLSyntax
    left::Bool
    right::Bool
    lateral::Bool

    JoinClause(;
               joinee,
               on,
               left = false,
               right = false,
               lateral = false) =
        new(joinee, on, left, right, lateral)
end

JoinClause(joinee; on, left = false, right = false, lateral = false) =
    JoinClause(; joinee, on, left, right, lateral)

JoinClause(joinee, on; left = false, right = false, lateral = false) =
    JoinClause(; joinee, on, left, right, lateral)

"""
    JOIN(; joinee, on, left = false, right = false, lateral = false, tail = nothing)
    JOIN(joinee; on, left = false, right = false, lateral = false, tail = nothing)
    JOIN(joinee, on; left = false, right = false, lateral = false, tail = nothing)

A `JOIN` clause.

# Examples

```jldoctest
julia> s = FROM(:p => :person) |>
           JOIN(:l => :location,
                on = FUN("=", (:p, :location_id), (:l, :location_id)),
                left = true) |>
           SELECT((:p, :person_id), (:l, :state));

julia> print(render(s))
SELECT
  "p"."person_id",
  "l"."state"
FROM "person" AS "p"
LEFT JOIN "location" AS "l" ON ("p"."location_id" = "l"."location_id")
```
"""
const JOIN = SQLSyntaxCtor{JoinClause}

function PrettyPrinting.quoteof(c::JoinClause, ctx::QuoteContext)
    ex = Expr(:call, :JOIN, quoteof([c.joinee, c.on], ctx)...)
    if c.left
        push!(ex.args, Expr(:kw, :left, c.left))
    end
    if c.right
        push!(ex.args, Expr(:kw, :right, c.right))
    end
    if c.lateral
        push!(ex.args, Expr(:kw, :lateral, c.lateral))
    end
    ex
end
