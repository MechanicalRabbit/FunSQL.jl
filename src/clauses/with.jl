# WITH clause.

mutable struct WithClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    recursive::Bool
    args::Vector{SQLClause}

    WithClause(;
               over = nothing,
               recursive = false,
               args) =
        new(over, recursive, args)
end

WithClause(args...; over = nothing, recursive = false) =
    WithClause(over = over, recursive = recursive, args = SQLClause[args...])

"""
    WITH(; over = nothing, recursive = false, args)
    WITH(args...; over = nothing, recursive = false)

A `WITH` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           WHERE(OP("IN", :person_id,
                          FROM(:essential_hypertension) |>
                          SELECT(:person_id))) |>
           SELECT(:person_id, :year_of_birth) |>
           WITH(FROM(:condition_occurrence) |>
                WHERE(OP("=", :condition_concept_id, 320128)) |>
                SELECT(:person_id) |>
                AS(:essential_hypertension));

julia> print(render(c))
WITH "essential_hypertension" AS (
  SELECT "person_id"
  FROM "condition_occurrence"
  WHERE ("condition_concept_id" = 320128)
)
SELECT
  "person_id",
  "year_of_birth"
FROM "person"
WHERE ("person_id" IN (
  SELECT "person_id"
  FROM "essential_hypertension"
))
```

```jldoctest
julia> c = FROM(:essential_hypertension) |>
           SELECT(OP("*")) |>
           WITH(recursive = true,
                FROM(:concept) |>
                WHERE(OP("=", :concept_id, 320128)) |>
                SELECT(:concept_id, :concept_name) |>
                UNION(all = true,
                      FROM(:eh => :essential_hypertension) |>
                      JOIN(:cr => :concept_relationship,
                           OP("=", (:eh, :concept_id), (:cr, :concept_id_1))) |>
                      JOIN(:c => :concept,
                           OP("=", (:cr, :concept_id_2), (:c, :concept_id))) |>
                      WHERE(OP("=", (:cr, :relationship_id), "Subsumes")) |>
                      SELECT((:c, :concept_id), (:c, :concept_name))) |>
                AS(:essential_hypertension, columns = [:concept_id, :concept_name]));

julia> print(render(c))
WITH RECURSIVE "essential_hypertension" ("concept_id", "concept_name") AS (
  SELECT
    "concept_id",
    "concept_name"
  FROM "concept"
  WHERE ("concept_id" = 320128)
  UNION ALL
  SELECT
    "c"."concept_id",
    "c"."concept_name"
  FROM "essential_hypertension" AS "eh"
  JOIN "concept_relationship" AS "cr" ON ("eh"."concept_id" = "cr"."concept_id_1")
  JOIN "concept" AS "c" ON ("cr"."concept_id_2" = "c"."concept_id")
  WHERE ("cr"."relationship_id" = 'Subsumes')
)
SELECT *
FROM "essential_hypertension"
```
"""
WITH(args...; kws...) =
    WithClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(WITH), pats::Vector{Any}) =
    dissect(scr, WithClause, pats)

function PrettyPrinting.quoteof(c::WithClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(WITH))
    if c.recursive !== false
        push!(ex.args, Expr(:kw, :recursive, c.recursive))
    end
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

rebase(c::WithClause, c′) =
    WithClause(over = rebase(c.over, c′), args = c.args, recursive = c.recursive)

