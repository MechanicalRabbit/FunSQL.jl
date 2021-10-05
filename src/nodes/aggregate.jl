# Aggregate expression.

mutable struct AggregateNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    name::Symbol
    distinct::Bool
    args::Vector{SQLNode}
    filter::Union{SQLNode, Nothing}

    AggregateNode(;
                  over = nothing,
                  name::Union{Symbol, AbstractString},
                  distinct = false,
                  args = SQLNode[],
                  filter = nothing) =
        new(over, Symbol(name), distinct, args, filter)
end

AggregateNode(name; over = nothing, distinct = false, args = SQLNode[], filter = nothing) =
    AggregateNode(over = over, name = name, distinct = distinct, args = args, filter = filter)

AggregateNode(name, args...; over = nothing, distinct = false, filter = nothing) =
    AggregateNode(over = over, name = name, distinct = distinct, args = SQLNode[args...], filter = filter)

"""
    Agg(; over = nothing, name, distinct = false, args = [], filter = nothing)
    Agg(name; over = nothing, distinct = false, args = [], filter = nothing)
    Agg(name, args...; over = nothing, distinct = false, filter = nothing)

An application of an aggregate function.

# Example

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group(Get.year_of_birth) |>
           Select(Get.year_of_birth, Agg.count());

julia> print(render(q))
SELECT "person_1"."year_of_birth", COUNT(*) AS "count"
FROM "person" AS "person_1"
GROUP BY "person_1"."year_of_birth"
```

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Group() |>
           Select(Agg.count(distinct = true, Get.year_of_birth));

julia> print(render(q))
SELECT COUNT(DISTINCT "person_1"."year_of_birth") AS "count"
FROM "person" AS "person_1"
```

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id]);

julia> visit_occurrence =
           SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date]);

julia> q = From(person) |>
           LeftJoin(:visit_group => From(visit_occurrence) |>
                                    Group(Get.person_id),
                    on = (Get.person_id .== Get.visit_group.person_id)) |>
           Select(Get.person_id,
                  :max_visit_start_date =>
                      Get.visit_group |> Agg.max(Get.visit_start_date));

julia> print(render(q))
SELECT "person_1"."person_id", "visit_group_1"."max" AS "max_visit_start_date"
FROM "person" AS "person_1"
LEFT JOIN (
  SELECT "visit_occurrence_1"."person_id", MAX("visit_occurrence_1"."visit_start_date") AS "max"
  FROM "visit_occurrence" AS "visit_occurrence_1"
  GROUP BY "visit_occurrence_1"."person_id"
) AS "visit_group_1" ON ("person_1"."person_id" = "visit_group_1"."person_id")
```
"""
Agg(args...; kws...) =
    AggregateNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Agg), pats::Vector{Any}) =
    dissect(scr, AggregateNode, pats)

function PrettyPrinting.quoteof(n::AggregateNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call,
              Expr(:., nameof(Agg),
                   QuoteNode(Base.isidentifier(n.name) ? n.name : string(n.name))))
    if n.distinct
        push!(ex.args, Expr(:kw, :distinct, n.distinct))
    end
    append!(ex.args, quoteof(n.args, qctx))
    if n.filter !== nothing
        push!(ex.args, Expr(:kw, :filter, quoteof(n.filter, qctx)))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

label(n::AggregateNode) =
    n.name

rebase(n::AggregateNode, n′) =
    AggregateNode(over = rebase(n.over, n′),
                  name = n.name,
                  distinct = n.distinct,
                  args = n.args,
                  filter = n.filter)


# Notation for making aggregate nodes.

struct AggClosure
    name::Symbol
end

Base.show(io::IO, f::AggClosure) =
    print(io, Expr(:., nameof(Agg),
                       QuoteNode(Base.isidentifier(f.name) ? f.name : string(f.name))))

Base.getproperty(::typeof(Agg), name::Symbol) =
    AggClosure(name)

Base.getproperty(::typeof(Agg), name::AbstractString) =
    AggClosure(Symbol(name))

(f::AggClosure)(args...; over = nothing, distinct = false, filter = nothing) =
    Agg(over = over, name = f.name, distinct = distinct, args = SQLNode[args...], filter = filter)

(f::AggClosure)(; over = nothing, distinct = false, args = SQLNode[], filter = nothing) =
    Agg(over = over, name = f.name, distinct = distinct, args = args, filter = filter)

