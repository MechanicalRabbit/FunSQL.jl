# GROUP BY clause.

module GROUPING_MODE

@enum GroupingMode::UInt8 begin
    ROLLUP
    CUBE
end

Base.convert(::Type{GroupingMode}, s::Symbol) =
    s in (:rollup, :ROLLUP) ?
        ROLLUP :
    s in (:cube, :CUBE) ?
        CUBE :
    throw(DomainError(QuoteNode(s), "expected :rollup or :cube"))

end

import .GROUPING_MODE.GroupingMode

mutable struct GroupClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    by::Vector{SQLClause}
    grouping_sets::Union{Vector{Vector{Int}}, GroupingMode, Nothing}

    function GroupClause(;
                over = nothing,
                by = SQLClause[],
                grouping_sets = nothing)
        c = new(over, by, grouping_sets isa Symbol ? convert(GroupingMode, grouping_sets) : grouping_sets)
        gs = c.grouping_sets
        if gs isa Vector{Vector{Int}} && !checkbounds(Bool, c.by, gs)
            throw(DomainError(gs, "grouping_sets is out of bounds"))
        end
        c
    end
end

GroupClause(by...; over = nothing, grouping_sets = nothing) =
    GroupClause(over = over, by = SQLClause[by...], grouping_sets = grouping_sets)

"""
    GROUP(; over = nothing, by = [], grouping_sets = nothing)
    GROUP(by...; over = nothing, grouping_sets = nothing)

A `GROUP BY` clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           GROUP(:year_of_birth) |>
           SELECT(:year_of_birth, AGG(:count));

julia> print(render(c))
SELECT
  "year_of_birth",
  count(*)
FROM "person"
GROUP BY "year_of_birth"
```
"""
GROUP(args...; kws...) =
    GroupClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(GROUP), pats::Vector{Any}) =
    dissect(scr, GroupClause, pats)

function PrettyPrinting.quoteof(c::GroupClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(GROUP))
    append!(ex.args, quoteof(c.by, ctx))
    gs = c.grouping_sets
    if gs !== nothing
        push!(ex.args, Expr(:kw, :grouping_sets, gs isa GroupingMode ? QuoteNode(Symbol(gs)) : gs))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::GroupClause, c′) =
    GroupClause(over = rebase(c.over, c′), by = c.by, grouping_sets = c.grouping_sets)

