# A With-like node that creates definitions for SELECT INTO statements.

mutable struct WithExternalNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    schema::Union{Symbol, Nothing}
    handler
    label_map::OrderedDict{Symbol, Int}

    function WithExternalNode(; over = nothing, args, schema = nothing, handler = nothing, label_map = nothing)
        if label_map !== nothing
            new(over, args, schema, handler, label_map)
        end
        n = new(over, args, schema, handler, OrderedDict{Symbol, Int}())
        populate_label_map!(n)
        n
    end
end

WithExternalNode(args...; over = nothing, schema = nothing, handler = nothing) =
    WithExternalNode(over = over, args = SQLNode[args...], schema = schema, handler = handler)

"""
    WithExternal(; over = nothing, args, schema = nothing, handler = nothing)
    WithExternal(args...; over = nothing, schema = nothing, handler = nothing)

`WithExternal` assigns a name to a temporary dataset.  The dataset could be
referred to by name in the `over` query.

The definition of the dataset is converted to a `Pair{SQLTable, SQLClause}`
object and sent to `handler`, which can use it, for instance, to construct
a `SELECT INTO` statement.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> condition_occurrence =
           SQLTable(:condition_occurrence, columns = [:condition_occurrence_id,
                                                      :person_id,
                                                      :condition_concept_id]);

julia> handler((tbl, def)) =
           println("CREATE TEMP TABLE ", render(ID(tbl.name)), " AS\\n",
                   render(def), ";");

julia> q = From(person) |>
           Where(Fun.in(Get.person_id, From(:essential_hypertension) |>
                                       Select(Get.person_id))) |>
           WithExternal(:essential_hypertension =>
                            From(condition_occurrence) |>
                            Where(Get.condition_concept_id .== 320128),
                        handler = handler);

julia> print(render(q))
CREATE TEMP TABLE "essential_hypertension" AS
SELECT "condition_occurrence_1"."person_id"
FROM "condition_occurrence" AS "condition_occurrence_1"
WHERE ("condition_occurrence_1"."condition_concept_id" = 320128);
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."person_id" IN (
  SELECT "essential_hypertension"."person_id"
  FROM "essential_hypertension"
))
```
"""
WithExternal(args...; kws...) =
    WithExternalNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(WithExternal), pats::Vector{Any}) =
    dissect(scr, WithExternalNode, pats)

function PrettyPrinting.quoteof(n::WithExternalNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(WithExternal))
    if isempty(n.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.args, ctx))
    end
    if n.schema !== nothing
        push!(ex.args, Expr(:kw, :schema, QuoteNode(n.schema)))
    end
    if n.handler !== nothing
        push!(ex.args, Expr(:kw, :handler, QuoteNode(nameof(n.handler))))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

label(n::WithExternalNode) =
    label(n.over)

rebase(n::WithExternalNode, n′) =
    WithExternalNode(over = rebase(n.over, n′), args = n.args, schema = n.schema, handler = n.handler)

