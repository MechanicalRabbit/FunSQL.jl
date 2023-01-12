# Sorting.

mutable struct OrderNode <: TabularNode
    over::Union{SQLNode, Nothing}
    by::Vector{SQLNode}

    OrderNode(; over = nothing, by) =
        new(over, by)
end

OrderNode(by...; over = nothing) =
    OrderNode(over = over, by = SQLNode[by...])

"""
    Order(; over = nothing, by)
    Order(by...; over = nothing)

`Order` sorts the input rows `by` the given key.

The `Order `node is translated to a query with an `ORDER BY` clause:
```sql
SELECT ...
FROM \$over
ORDER BY \$by...
```

Specify the sort order with [`Asc`](@ref), [`Desc`](@ref), or [`Sort`](@ref).

# Examples

*List patients ordered by their age.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Order(Get.year_of_birth);

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
ORDER BY "person_1"."year_of_birth"
```
"""
Order(args...; kws...) =
    OrderNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Order), pats::Vector{Any}) =
    dissect(scr, OrderNode, pats)

transliterate(tag::Val{:order}, ctx::TransliterateContext, @nospecialize(by...)) =
    transliterate(tag, ctx; by = Expr(:vect, by...))

transliterate(::Val{:order}, ctx::TransliterateContext; by) =
    Order(by = transliterate(Vector{SQLNode}, by, ctx))

function PrettyPrinting.quoteof(n::OrderNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Order))
    if isempty(n.by)
        push!(ex.args, Expr(:kw, :by, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.by, ctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::OrderNode) =
    label(n.over)

rebase(n::OrderNode, n′) =
    OrderNode(over = rebase(n.over, n′), by = n.by)

