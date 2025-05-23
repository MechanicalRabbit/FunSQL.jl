# WITH clause.

struct WithClause <: AbstractSQLClause
    recursive::Bool
    args::Vector{SQLSyntax}

    WithClause(;
               recursive = false,
               args) =
        new(recursive, args)
end

WithClause(args...; recursive = false) =
    WithClause(; recursive, args = SQLSyntax[args...])

"""
    WITH(; recursive = false, args, tail = nothing)
    WITH(args...; recursive = false, tail = nothing)

A `WITH` clause.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           WHERE(FUN(:in, :person_id,
                          FROM(:essential_hypertension) |>
                          SELECT(:person_id))) |>
           SELECT(:person_id, :year_of_birth) |>
           WITH(FROM(:condition_occurrence) |>
                WHERE(FUN("=", :condition_concept_id, 320128)) |>
                SELECT(:person_id) |>
                AS(:essential_hypertension));

julia> print(render(s))
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
julia> s = FROM(:essential_hypertension) |>
           SELECT(*) |>
           WITH(recursive = true,
                FROM(:concept) |>
                WHERE(FUN("=", :concept_id, 320128)) |>
                SELECT(:concept_id, :concept_name) |>
                UNION(all = true,
                      FROM(:eh => :essential_hypertension) |>
                      JOIN(:cr => :concept_relationship,
                           FUN("=", (:eh, :concept_id), (:cr, :concept_id_1))) |>
                      JOIN(:c => :concept,
                           FUN("=", (:cr, :concept_id_2), (:c, :concept_id))) |>
                      WHERE(FUN("=", (:cr, :relationship_id), "Subsumes")) |>
                      SELECT((:c, :concept_id), (:c, :concept_name))) |>
                AS(:essential_hypertension, columns = [:concept_id, :concept_name]));

julia> print(render(s))
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
const WITH = SQLSyntaxCtor{WithClause}(:WITH)

function PrettyPrinting.quoteof(c::WithClause, ctx::QuoteContext)
    ex = Expr(:call, :WITH)
    if c.recursive !== false
        push!(ex.args, Expr(:kw, :recursive, c.recursive))
    end
    if isempty(c.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(c.args, ctx))
    end
    ex
end
