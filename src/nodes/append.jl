# Append (UNION ALL) node.

mutable struct AppendNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}

    AppendNode(; over = nothing, args) =
        new(over, args)
end

AppendNode(args...; over = nothing) =
    AppendNode(over = over, args = SQLNode[args...])

"""
    Append(; over = nothing, args)
    Append(args...; over = nothing)

`Append` concatenates input datasets.

Only the columns that are present in every input dataset will be included
to the output of `Append`.

An `Append` node is translated to a `UNION ALL` query:
```sql
SELECT ...
FROM \$over
UNION ALL
SELECT ...
FROM \$(args[1])
UNION ALL
...
```

# Examples

*Show the dates of all measuments and observations.*

```jldoctest
julia> measurement = SQLTable(:measurement, columns = [:measurement_id, :person_id, :measurement_date]);

julia> observation = SQLTable(:observation, columns = [:observation_id, :person_id, :observation_date]);

julia> q = From(:measurement) |>
           Define(:date => Get.measurement_date) |>
           Append(From(:observation) |>
                  Define(:date => Get.observation_date));

julia> print(render(q, tables = [measurement, observation]))
SELECT
  "measurement_1"."person_id",
  "measurement_1"."measurement_date" AS "date"
FROM "measurement" AS "measurement_1"
UNION ALL
SELECT
  "observation_1"."person_id",
  "observation_1"."observation_date" AS "date"
FROM "observation" AS "observation_1"
```
"""
Append(args...; kws...) =
    AppendNode(args...; kws...) |> SQLNode

funsql(::Val{:append}, args...; kws...) =
    Append(args...; kws...)

dissect(scr::Symbol, ::typeof(Append), pats::Vector{Any}) =
    dissect(scr, AppendNode, pats)

function PrettyPrinting.quoteof(n::AppendNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Append))
    if isempty(n.args)
        push!(ex.args, Expr(:kw, :args, Expr(:vect)))
    else
        append!(ex.args, quoteof(n.args, ctx))
    end
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
    end
    ex
end

function label(n::AppendNode)
    lbl = label(n.over)
    for l in n.args
        label(l) === lbl || return :union
    end
    lbl
end

rebase(n::AppendNode, n′) =
    AppendNode(over = rebase(n.over, n′), args = n.args)
