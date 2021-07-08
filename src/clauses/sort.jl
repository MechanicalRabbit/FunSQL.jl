# Sort ordering indicator.

module VALUE_ORDER

@enum ValueOrder::UInt8 begin
    ASC
    DESC
end

Base.convert(::Type{ValueOrder}, s::Symbol) =
    s in (:asc, :ASC) ?
        ASC :
    s in (:desc, :DESC) ?
        DESC :
    throw(DomainError(QuoteNode(s),
                      "expected :asc or :desc"))

end

import .VALUE_ORDER.ValueOrder

module NULLS_ORDER

@enum NullsOrder::UInt8 begin
    NULLS_FIRST
    NULLS_LAST
end

Base.convert(::Type{NullsOrder}, s::Symbol) =
    s in (:first, :FIRST, :nulls_first, :NULLS_FIRST) ?
        NULLS_FIRST :
    s in (:last, :LAST, :nulls_last, :NULLS_LAST) ?
        NULLS_LAST :
    throw(DomainError(QuoteNode(s),
                      "expected :nulls_first or :nulls_last"))

end

import .NULLS_ORDER.NullsOrder

mutable struct SortClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    value::ValueOrder
    nulls::Union{NullsOrder, Nothing}

    SortClause(;
               over = nothing,
               value,
               nulls = nothing) =
        new(over, value, nulls)
end

SortClause(value; over = nothing, nulls = nothing) =
    SortClause(over = over, value = value, nulls = nulls)

"""
    SORT(; over = nothing, value, nulls = nothing)
    SORT(value; over = nothing, nulls = nothing)
    ASC(; over = nothing, nulls = nothing)
    DESC(; over = nothing, nulls = nothing)

Sort order options.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           ORDER(:year_of_birth |> DESC()) |>
           SELECT(:person_id);

julia> print(render(c))
SELECT "person_id"
FROM "person"
ORDER BY "year_of_birth" DESC
```
"""
SORT(args...; kws...) =
    SortClause(args...; kws...) |> SQLClause

"""
    ASC(; over = nothing, nulls = nothing)

Ascending order indicator.
"""
ASC(; kws...) =
    SORT(VALUE_ORDER.ASC; kws...)

"""
    DESC(; over = nothing, nulls = nothing)

Descending order indicator.
"""
DESC(; kws...) =
    SORT(VALUE_ORDER.DESC; kws...)

dissect(scr::Symbol, ::typeof(SORT), pats::Vector{Any}) =
    dissect(scr, SortClause, pats)

function PrettyPrinting.quoteof(c::SortClause, qctx::SQLClauseQuoteContext)
    if c.value == VALUE_ORDER.ASC
        ex = Expr(:call, nameof(ASC))
    elseif c.value == VALUE_ORDER.DESC
        ex = Expr(:call, nameof(DESC))
    else
        ex = Expr(:call, nameof(SORT), QuoteNode(Symbol(c.value)))
    end
    if c.nulls !== nothing
        push!(ex.args, Expr(:kw, :nulls, QuoteNode(Symbol(c.nulls))))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::SortClause, c′) =
    SortClause(over = rebase(c.over, c′), value = c.value, nulls = c.nulls)

