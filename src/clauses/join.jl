# JOIN clause.

mutable struct JoinClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    joinee::SQLClause
    on::SQLClause
    left::Bool
    right::Bool
    lateral::Bool

    JoinClause(;
               over = nothing,
               joinee,
               on,
               left = false,
               right = false,
               lateral = false) =
        new(over, joinee, on, left, right, lateral)
end

JoinClause(joinee; over = nothing, on, left = false, right = false, lateral = false) =
    JoinClause(over = over, joinee = joinee, on = on, left = left, right = right, lateral = lateral)

JoinClause(joinee, on; over = nothing, left = false, right = false, lateral = false) =
    JoinClause(over = over, joinee = joinee, on = on, left = left, right = right, lateral = lateral)

"""
    JOIN(; over = nothing, joinee, on, left = false, right = false, lateral = false)
    JOIN(joinee; over = nothing, on, left = false, right = false, lateral = false)
    JOIN(joinee, on; over = nothing, left = false, right = false, lateral = false)

A `JOIN` clause.

# Examples

```jldoctest
julia> c = FROM(:p => :person) |>
           JOIN(:l => :location,
                on = OP("=", (:p, :location_id), (:l, :location_id)),
                left = true) |>
           SELECT((:p, :person_id), (:l, :state));

julia> print(render(c))
SELECT "p"."person_id", "l"."state"
FROM "person" AS "p"
LEFT JOIN "location" AS "l" ON ("p"."location_id" = "l"."location_id")
```
"""
JOIN(args...; kws...) =
    JoinClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(JOIN), pats::Vector{Any}) =
    dissect(scr, JoinClause, pats)

function PrettyPrinting.quoteof(c::JoinClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(JOIN), quoteof([c.joinee, c.on], ctx)...)
    if c.left
        push!(ex.args, Expr(:kw, :left, c.left))
    end
    if c.right
        push!(ex.args, Expr(:kw, :right, c.right))
    end
    if c.lateral
        push!(ex.args, Expr(:kw, :lateral, c.lateral))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::JoinClause, c′) =
    JoinClause(over = rebase(c.over, c′),
               joinee = c.joinee, on = c.on, left = c.left, right = c.right, lateral = c.lateral)

