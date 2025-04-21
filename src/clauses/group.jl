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

struct GroupClause <: AbstractSQLClause
    by::Vector{SQLSyntax}
    sets::Union{Vector{Vector{Int}}, GroupingMode, Nothing}

    function GroupClause(;
                by = SQLSyntax[],
                sets = nothing)
        c = new(by, sets isa Symbol ? convert(GroupingMode, sets) : sets)
        s = c.sets
        if s isa Vector{Vector{Int}} && !checkbounds(Bool, c.by, s)
            throw(DomainError(s, "sets are out of bounds"))
        end
        c
    end
end

GroupClause(by...; sets = nothing) =
    GroupClause(; by = SQLSyntax[by...], sets)

"""
    GROUP(; by = [], sets = nothing, tail = nothing)
    GROUP(by...; sets = nothing, tail = nothing)

A `GROUP BY` clause.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           GROUP(:year_of_birth) |>
           SELECT(:year_of_birth, AGG(:count));

julia> print(render(s))
SELECT
  "year_of_birth",
  count(*)
FROM "person"
GROUP BY "year_of_birth"
```
"""
const GROUP = SQLSyntaxCtor{GroupClause}

function PrettyPrinting.quoteof(c::GroupClause, ctx::QuoteContext)
    ex = Expr(:call, :GROUP)
    append!(ex.args, quoteof(c.by, ctx))
    s = c.sets
    if s !== nothing
        push!(ex.args, Expr(:kw, :sets, s isa GroupingMode ? QuoteNode(Symbol(s)) : s))
    end
    ex
end
