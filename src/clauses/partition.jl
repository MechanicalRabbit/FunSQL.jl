# Window definition clause.

@enum FrameMode::UInt8 begin
    RANGE_MODE
    ROWS_MODE
    GROUPS_MODE
end

Base.convert(::Type{FrameMode}, s::Symbol) =
    s in (:range, :range_mode, :RANGE, :RANGE_MODE) ?
        RANGE_MODE :
    s in (:rows, :rows_mode, :ROWS, :ROWS_MODE) ?
        ROWS_MODE :
    s in (:groups, :groups_mode, :GROUPS, :GROUPS_MODE) ?
        GROUPS_MODE :
    throw(DomainError(QuoteNode(s),
                      "expected :range, :rows, or :groups"))

@enum FrameExclusion::UInt8 begin
    EXCLUDE_NO_OTHERS
    EXCLUDE_CURRENT_ROW
    EXCLUDE_GROUP
    EXCLUDE_TIES
end

Base.convert(::Type{FrameExclusion}, s::Symbol) =
    s in (:no_others, :exclude_no_others, :NO_OTHERS, :EXCLUDE_NO_OTHERS) ?
        EXCLUDE_NO_OTHERS :
    s in (:current_row, :exclude_current_row, :CURRENT_ROW, :EXCLUDE_CURRENT_ROW) ?
        EXCLUDE_CURRENT_ROW :
    s in (:group, :exclude_group, :GROUP, :EXCLUDE_GROUP) ?
        EXCLUDE_GROUP :
    s in (:ties, :exclude_ties, :TIES, :EXCLUDE_TIES) ?
        EXCLUDE_TIES :
    throw(DomainError(QuoteNode(s),
                      "expected :no_others, :current_row, :group, or :ties"))

struct PartitionFrame
    mode::FrameMode
    start::Any
    finish::Any
    exclude::Union{FrameExclusion, Nothing}

    PartitionFrame(; mode, start = nothing, finish = nothing, exclude = nothing) =
        new(mode, start, finish, exclude)
end

Base.convert(::Type{PartitionFrame}, t::NamedTuple) =
    PartitionFrame(; t...)

Base.convert(::Type{PartitionFrame}, m::Union{FrameMode, Symbol}) =
    PartitionFrame(mode = m)

function PrettyPrinting.quoteof(f::PartitionFrame)
    if f.start === nothing && f.finish === nothing && f.exclude === nothing
        return QuoteNode(Symbol(f.mode))
    end
    ex = Expr(:tuple, Expr(:(=), :mode, QuoteNode(Symbol(f.mode))))
    if f.start !== nothing
        push!(ex.args, Expr(:(=), :start, f.start))
    end
    if f.finish !== nothing
        push!(ex.args, Expr(:(=), :finish, f.finish))
    end
    if f.exclude !== nothing
        push!(ex.args, Expr(:(=), :exclude, QuoteNode(Symbol(f.exclude))))
    end
    ex
end

mutable struct PartitionClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    by::Vector{SQLClause}
    order_by::Vector{SQLClause}
    frame::Union{PartitionFrame, Nothing}

    PartitionClause(; over = nothing, by = SQLClause[], order_by = SQLClause[], frame = nothing) =
        new(over, by, order_by, frame)
end

PartitionClause(by...; over = nothing, order_by = SQLClause[], frame = nothing) =
    PartitionClause(over = over, by = SQLClause[by...], order_by = order_by, frame = frame)

"""
    PARTITION(; over = nothing, by = [], order_by = [], frame = nothing)
    PARTITION(by...; over = nothing, order_by = [], frame = nothing)

A window definition clause.

# Examples

```jldoctest
julia> c = FROM(:person) |>
           SELECT(:person_id,
                  AGG("ROW_NUMBER", over = PARTITION(:year_of_birth)));

julia> print(render(c))
SELECT "person_id", (ROW_NUMBER() OVER (PARTITION BY "year_of_birth"))
FROM "person"
```

```jldoctest
julia> c = FROM(:person) |>
           WINDOW(:w1 => PARTITION(:year_of_birth),
                  :w2 => :w1 |> PARTITION(order_by = [:month_of_birth, :day_of_birth])) |>
           SELECT(:person_id, AGG("ROW_NUMBER", over = :w2));

julia> print(render(c))
SELECT "person_id", (ROW_NUMBER() OVER ("w2"))
FROM "person"
WINDOW "w1" AS (PARTITION BY "year_of_birth"), "w2" AS ("w1" ORDER BY "month_of_birth", "day_of_birth")
```

```jldoctest
julia> c = FROM(:person) |>
           GROUP(:year_of_birth) |>
           SELECT(:year_of_birth,
                  AGG("AVG",
                      AGG("COUNT", OP("*")),
                      over = PARTITION(order_by = [:year_of_birth],
                                       frame = (mode = :range, start = -1, finish = 1))));

julia> print(render(c))
SELECT "year_of_birth", (AVG(COUNT(*)) OVER (ORDER BY "year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING))
FROM "person"
GROUP BY "year_of_birth"
```
"""
PARTITION(args...; kws...) =
    PartitionClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(PARTITION), pats::Vector{Any}) =
    dissect(scr, PartitionClause, pats)

function PrettyPrinting.quoteof(c::PartitionClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(PARTITION))
    append!(ex.args, quoteof(c.by, qctx))
    if !isempty(c.order_by)
        push!(ex.args, Expr(:kw, :order_by, Expr(:vect, quoteof(c.order_by, qctx)...)))
    end
    if c.frame !== nothing
        push!(ex.args, Expr(:kw, :frame, quoteof(c.frame)))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, qctx), ex)
    end
    ex
end

rebase(c::PartitionClause, c′) =
    PartitionClause(over = rebase(c.over, c′), by = c.by, order_by = c.order_by, frame = c.frame)

