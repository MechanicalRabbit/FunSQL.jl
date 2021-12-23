# Selecting.

mutable struct SelectNode <: TabularNode
    over::Union{SQLNode, Nothing}
    args::Vector{SQLNode}
    label_map::OrderedDict{Symbol, Int}

    function SelectNode(; over = nothing, args, label_map = nothing)
        if label_map !== nothing
            return new(over, args, label_map)
        end
        n = new(over, args, OrderedDict{Symbol, Int}())
        for (i, arg) in enumerate(n.args)
            name = label(arg)
            if name in keys(n.label_map)
                err = DuplicateLabelError(name, path = [arg, n])
                throw(err)
            end
            n.label_map[name] = i
        end
        n
    end
end

SelectNode(args...; over = nothing) =
    SelectNode(over = over, args = SQLNode[args...])

"""
    Select(; over; args)
    Select(args...; over)

The `Select` node specifies the output columns.

```sql
SELECT \$args...
FROM \$over
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           Select(Get.person_id);

julia> print(render(q))
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
```
"""
Select(args...; kws...) =
    SelectNode(args...; kws...) |> SQLNode

dissect(scr::Symbol, ::typeof(Select), pats::Vector{Any}) =
    dissect(scr, SelectNode, pats)

function PrettyPrinting.quoteof(n::SelectNode, ctx::QuoteContext)
    ex = Expr(:call, nameof(Select))
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

label(n::SelectNode) =
    label(n.over)

rebase(n::SelectNode, n′) =
    SelectNode(over = rebase(n.over, n′), args = n.args, label_map = n.label_map)

