# From node.

struct SelfSource
end

struct ValuesSource
    columns::NamedTuple
end

struct FunctionSource
    node::SQLNode
    columns::Vector{Symbol}
end

_from_source(source::Union{SQLTable, Symbol, SelfSource, FunctionSource, ValuesSource, Nothing}) =
    source

_from_source(source::AbstractString) =
    Symbol(source)

_from_source(::typeof(^)) =
    SelfSource()

function _from_source(node::AbstractSQLNode;
                      columns::AbstractVector{<:Union{Symbol, AbstractString}})
    source = FunctionSource(node,
                            !isa(columns, Vector{Symbol}) ?
                                Symbol[Symbol(col) for col in columns] :
                                columns)
    seen = Set{Symbol}()
    for col in source.columns
        if col in seen
            err = DuplicateLabelError(col, path = [From(source)])
            throw(err)
        end
        push!(seen, col)
    end
    source
end

function _from_source(source)
    columns = Tables.columntable(source)
    length(columns) > 0 || throw(DomainError(source, "a table with at least one column is expected"))
    ValuesSource(columns)
end

mutable struct FromNode <: TabularNode
    source::Union{SQLTable, Symbol, SelfSource, ValuesSource, FunctionSource, Nothing}

    FromNode(; source, kws...) =
        new(_from_source(source; kws...))
end

FromNode(source; kws...) =
    FromNode(source = source; kws...)

"""
    From(; source)
    From(tbl::SQLTable)
    From(name::Symbol)
    From(^)
    From(df)
    From(f::SQLNode; columns::Vector{Symbol})
    From(::Nothing)

`From` outputs the content of a database table.

The parameter `source` could be one of:
* a [`SQLTable`](@ref) object;
* a `Symbol` value;
* a `^` object;
* a `DataFrame` or any Tables.jl-compatible dataset;
* A `SQLNode` representing a table-valued function.  In this case, `From`
  also requires a keyword parameter `columns` with a list of output columns
  produced by the function.
* `nothing`.
When `source` is a symbol, it can refer to either a table in
[`SQLCatalog`](@ref) or an intermediate dataset defined with the [`With`](@ref)
node.

The `From` node is translated to a SQL query with a `FROM` clause:
```sql
SELECT ...
FROM \$source
```

`From(^)` must be a component of [`Iterate`](@ref).  In the context of
 [`Iterate`](@ref), it refers to the output of the previous iteration.

`From(::DataFrame)` is translated to a `VALUES` clause.

`From(nothing)` emits a dataset with one row and no columns and can usually
be omitted.

# Examples

*List all patients.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> print(render(q))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
```

*List all patients.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person);

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
```

*Show all patients diagnosed with essential hypertension.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> condition_occurrence =
           SQLTable(:condition_occurrence,
                    columns = [:condition_occurrence_id, :person_id, :condition_concept_id]);

julia> q = From(:person) |>
           Where(Fun.in(Get.person_id, From(:essential_hypertension) |>
                                       Select(Get.person_id))) |>
           With(:essential_hypertension =>
                    From(:condition_occurrence) |>
                    Where(Get.condition_concept_id .== 320128));

julia> print(render(q, tables = [person, condition_occurrence]))
WITH "essential_hypertension_1" ("person_id") AS (
  SELECT "condition_occurrence_1"."person_id"
  FROM "condition_occurrence" AS "condition_occurrence_1"
  WHERE ("condition_occurrence_1"."condition_concept_id" = 320128)
)
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."person_id" IN (
  SELECT "essential_hypertension_2"."person_id"
  FROM "essential_hypertension_1" AS "essential_hypertension_2"
))
```

*Show the current date.*

```jldoctest
julia> q = From(nothing) |>
           Select(Fun.current_date());

julia> print(render(q))
SELECT CURRENT_DATE AS "current_date"

julia> q = Select(Fun.current_date());

julia> print(render(q))
SELECT CURRENT_DATE AS "current_date"
```

Query a `DataFrame`.

```jldoctest
julia> df = DataFrame(name = ["SQL", "Julia", "FunSQL"],
                      year = [1974, 2012, 2021]);

julia> q = From(df) |>
           Group() |>
           Select(Agg.min(Get.year), Agg.max(Get.year));

julia> print(render(q))
SELECT
  min("values_1"."year") AS "min",
  max("values_1"."year") AS "max"
FROM (
  VALUES
    (1974),
    (2012),
    (2021)
) AS "values_1" ("year")
```

Parse comma-separated numbers.

```jldoctest
julia> q = From(Fun.regexp_matches("2,3,5,7,11", "(\\\\d+)", "g"),
                columns = [:captures]) |>
           Select(Fun."CAST(?[1] AS INTEGER)"(Get.captures));

julia> print(render(q, dialect = :postgresql))
SELECT CAST("regexp_matches_1"."captures"[1] AS INTEGER) AS "_"
FROM regexp_matches('2,3,5,7,11', '(\\d+)', 'g') AS "regexp_matches_1" ("captures")
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
    elseif source isa SelfSource
        Expr(:call, nameof(From), :^)
    elseif source isa ValuesSource
        Expr(:call, nameof(From), quoteof(source.columns, ctx))
    elseif source isa FunctionSource
        Expr(:call, nameof(From),
                    quoteof(source.node, ctx),
                    Expr(:kw, :columns, Expr(:vect, [QuoteNode(col) for col in source.columns]...)))
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
    elseif source isa ValuesSource
        :values
    elseif source isa FunctionSource
        label(source.node)
    else
        :_
    end
end
