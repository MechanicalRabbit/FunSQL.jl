# Sort ordering.

mutable struct SortNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    value::ValueOrder
    nulls::Union{NullsOrder, Nothing}

    SortNode(;
             over = nothing,
             value,
             nulls = nothing) =
        new(over, value, nulls)
end

SortNode(value; over = nothing, nulls = nothing) =
    SortNode(over = over, value = value, nulls = nulls)

"""
    Sort(; over = nothing, value, nulls = nothing)
    Sort(value; over = nothing, nulls = nothing)
    Asc(; over = nothing, nulls = nothing)
    Desc(; over = nothing, nulls = nothing)

Sort order indicator.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Order(Get.year_of_birth |> Desc());

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth" DESC
```
"""
Sort(args...; kws...) =
    SortNode(args...; kws...) |> SQLNode

"""
    Asc(; over = nothing, nulls = nothing)

Ascending order indicator.
"""
Asc(; kws...) =
    Sort(VALUE_ORDER.ASC; kws...)

"""
    Desc(; over = nothing, nulls = nothing)

Descending order indicator.
"""
Desc(; kws...) =
    Sort(VALUE_ORDER.DESC; kws...)

dissect(scr::Symbol, ::typeof(Sort), pats::Vector{Any}) =
    dissect(scr, SortNode, pats)

function PrettyPrinting.quoteof(n::SortNode, ctx::QuoteContext)
    if n.value == VALUE_ORDER.ASC
        ex = Expr(:call, nameof(Asc))
    elseif n.value == VALUE_ORDER.DESC
        ex = Expr(:call, nameof(Desc))
    else
        ex = Expr(:call, nameof(Sort), QuoteNode(Symbol(n.value)))
    end
    if n.nulls !== nothing
        push!(ex.args, Expr(:kw, :nulls, QuoteNode(Symbol(n.nulls))))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::SortNode) =
    label(n.over)

rebase(n::SortNode, n′) =
    SortNode(over = rebase(n.over, n′), value = n.value, nulls = n.nulls)

