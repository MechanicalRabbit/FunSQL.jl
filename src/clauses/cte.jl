# AS clause for a common table expression.

mutable struct CTEClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    name::Symbol
    columns::Union{Vector{Symbol}, Nothing}
    materialized::Union{Bool, Nothing}

    CTEClause(;
              over = nothing,
              name::Union{Symbol, AbstractString},
              columns::Union{AbstractVector{<:Union{Symbol, AbstractString}}, Nothing} = nothing,
              materialized = nothing) =
        new(over,
            Symbol(name),
            !(columns isa Union{Vector{Symbol}, Nothing}) ?
                Symbol[Symbol(col) for col in columns] : columns,
            materialized)
end

CTEClause(name; over = nothing, columns = nothing, materialized = nothing) =
    CTEClause(over = over, name = name, columns = columns, materialized = materialized)

"""
    CTE(; over = nothing, name, columns = nothing, materialized = nothing)
    CTE(name; over = nothing, columns = nothing, materialized = nothing)

An `AS` clause for a common table expression.

# Examples

```jldoctest
julia> c = FROM(:condition_occurrence) |>
           WHERE(OP("=", :condition_concept_id, 320128)) |>
           SELECT(:person_id) |>
           CTE(:essential_hypertension);

julia> print(render(c))
"essential_hypertension" AS (
  SELECT "person_id"
  FROM "condition_occurrence"
  WHERE ("condition_concept_id" = 320128)
)
```
"""
CTE(args...; kws...) =
    CTEClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(CTE), pats::Vector{Any}) =
    dissect(scr, CTEClause, pats)

function PrettyPrinting.quoteof(c::CTEClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(CTE), quoteof(c.name))
    if c.columns !== nothing
        push!(ex.args, Expr(:kw, :columns, Expr(:vect, quoteof(c.columns, ctx)...)))
    end
    if c.materialized !== nothing
        push!(ex.args, Expr(:kw, :materialized, c.materialized))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::CTEClause, c′) =
    CTEClause(over = rebase(c.over, c′), name = c.name, columns = c.columns, materialized = c.materialized)

