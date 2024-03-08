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
    sets::Union{Vector{Vector{Int}}, GroupingMode, Nothing}

    function GroupClause(;
                over = nothing,
                by = SQLClause[],
                sets = nothing)
        c = new(over, by, sets isa Symbol ? convert(GroupingMode, sets) : sets)
        s = c.sets
        if s isa Vector{Vector{Int}} && !checkbounds(Bool, c.by, s)
            throw(DomainError(s, "sets are out of bounds"))
        end
        c
    end
end

GroupClause(by...; over = nothing, sets = nothing) =
    GroupClause(over = over, by = SQLClause[by...], sets = sets)

"""
    GROUP(; over = nothing, by = [], sets = nothing)
    GROUP(by...; over = nothing, sets = nothing)

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
    s = c.sets
    if s !== nothing
        push!(ex.args, Expr(:kw, :sets, s isa GroupingMode ? QuoteNode(Symbol(s)) : s))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::GroupClause, c′) =
    GroupClause(over = rebase(c.over, c′), by = c.by, sets = c.sets)

