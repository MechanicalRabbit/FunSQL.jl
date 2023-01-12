# Where node.

mutable struct WhereNode <: TabularNode
    over::Union{SQLNode, Nothing}
    condition::SQLNode

    WhereNode(; over = nothing, condition) =
        new(over, condition)
end

WhereNode(condition; over = nothing) =
    WhereNode(over = over, condition = condition)

"""
    Where(; over = nothing, condition)
    Where(condition; over = nothing)

The `Where` node filters the input rows by the given `condition`.

`Where` is translated to a SQL query with a `WHERE` clause:
```sql
SELECT ...
FROM \$over
WHERE \$condition
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Where(Fun(">", Get.year_of_birth, 2000));

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."year_of_birth" > 2000)
```
"""
Where(args...; kws...) =
    WhereNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Where), pats::Vector{Any}) =
    dissect(scr, WhereNode, pats)

transliterate(tag::Val{:where}, ctx::TransliterateContext, @nospecialize(condition)) =
    transliterate(tag, ctx, condition = condition)

transliterate(::Val{:where}, ctx::TransliterateContext; condition) =
    Where(condition = transliterate(SQLNode, condition, ctx))

transliterate(tag::Val{:filter}, ctx::TransliterateContext, @nospecialize(condition)) =
    transliterate(tag, ctx, condition = condition)

transliterate(::Val{:filter}, ctx::TransliterateContext; condition) =
    Where(condition = transliterate(SQLNode, condition, ctx))

function PrettyPrinting.quoteof(n::WhereNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Where), quoteof(n.condition, ctx))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::WhereNode) =
    label(n.over)

rebase(n::WhereNode, n′) =
    WhereNode(over = rebase(n.over, n′), condition = n.condition)

