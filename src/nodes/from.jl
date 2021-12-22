# From node.

mutable struct FromNode <: TabularNode
    source::Union{SQLTable, Symbol, Nothing}

    FromNode(; source) =
        new(source isa AbstractString ? Symbol(source) : source)
end

FromNode(source) =
    FromNode(source = source)

"""
    From(; source)
    From(source)

`From` outputs the content of a database table.  The parameter `source`
could be a [`SQLTable`](@ref) object, a symbol (for use with [`With`](@ref)),
or `nothing`.

```sql
SELECT ...
FROM \$source
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> print(render(q))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
```

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> condition_occurrence =
           SQLTable(:condition_occurrence, columns = [:condition_occurrence_id,
                                                      :person_id,
                                                      :condition_concept_id]);

julia> q = From(person) |>
           Where(Fun.in(Get.person_id, From(:essential_hypertension) |>
                                       Select(Get.person_id))) |>
           With(:essential_hypertension =>
                    From(condition_occurrence) |>
                    Where(Get.condition_concept_id .== 320128));

julia> print(render(q))
WITH "essential_hypertension_1" AS (
  SELECT "condition_occurrence_1"."person_id"
  FROM "condition_occurrence" AS "condition_occurrence_1"
  WHERE ("condition_occurrence_1"."condition_concept_id" = 320128)
)
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."person_id" IN (
  SELECT "essential_hypertension_1"."person_id"
  FROM "essential_hypertension_1"
))
```

```jldoctest
julia> q = From(nothing);

julia> print(render(q))
SELECT NULL
```
"""
From(args...; kws...) =
    FromNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(From), pats::Vector{Any}) =
    dissect(scr, FromNode, pats)

Base.convert(::Type{AbstractSQLNode}, source::SQLTable) =
    FromNode(source)

function PrettyPrinting.quoteof(n::FromNode, ctx::QuoteContext)
    source = n.source
    if source isa SQLTable
        tex = get(ctx.vars, source, nothing)
        if tex === nothing
            tex = quoteof(source, limit = true)
        end
        Expr(:call, nameof(From), tex)
    elseif source isa Symbol
        Expr(:call, nameof(From), QuoteNode(source))
    else
        Expr(:call, nameof(From), source)
    end
end

function label(n::FromNode)
    source = n.source
    if source isa SQLTable
        source.name
    elseif source isa Symbol
        source
    else
        :_
    end
end

