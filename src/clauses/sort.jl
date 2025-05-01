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

struct SortClause <: AbstractSQLClause
    value::ValueOrder
    nulls::Union{NullsOrder, Nothing}

    SortClause(;
               value,
               nulls = nothing) =
        new(value, nulls)
end

SortClause(value; nulls = nothing) =
    SortClause(; value, nulls)

"""
    SORT(; value, nulls = nothing, tail = nothing)
    SORT(value; nulls = nothing, tail = nothing)
    ASC(; nulls = nothing, tail = nothing)
    DESC(; nulls = nothing, tail = nothing)

Sort order options.

# Examples

```jldoctest
julia> s = FROM(:person) |>
           ORDER(:year_of_birth |> DESC()) |>
           SELECT(:person_id);

julia> print(render(s))
SELECT "person_id"
FROM "person"
ORDER BY "year_of_birth" DESC
```
"""
SORT = SQLSyntaxCtor{SortClause}(:SORT)

"""
    ASC(; over = nothing, nulls = nothing, tail = nothing)

Ascending order indicator.
"""
ASC(; kws...) =
    SORT(VALUE_ORDER.ASC; kws...)

"""
    DESC(; over = nothing, nulls = nothing, tail = nothing)

Descending order indicator.
"""
DESC(; kws...) =
    SORT(VALUE_ORDER.DESC; kws...)

function PrettyPrinting.quoteof(c::SortClause, ctx::QuoteContext)
    if c.value == VALUE_ORDER.ASC
        ex = Expr(:call, :ASC)
    elseif c.value == VALUE_ORDER.DESC
        ex = Expr(:call, :DESC)
    else
        ex = Expr(:call, :SORT, QuoteNode(Symbol(c.value)))
    end
    if c.nulls !== nothing
        push!(ex.args, Expr(:kw, :nulls, QuoteNode(Symbol(c.nulls))))
    end
    ex
end
