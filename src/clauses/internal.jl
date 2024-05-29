# Auxiliary clauses.

# Context holder for the serialize pass.

mutable struct WithContextClause <: AbstractSQLClause
    over::SQLClause
    dialect::SQLDialect
    columns::Union{Vector{SQLColumn}, Nothing}

    WithContextClause(; over, dialect, columns = nothing) =
        new(over, dialect, columns)
end

WITH_CONTEXT(args...; kws...) =
    WithContextClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(WITH_CONTEXT), pats::Vector{Any}) =
    dissect(scr, WithContextClause, pats)

function PrettyPrinting.quoteof(c::WithContextClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(WITH_CONTEXT), Expr(:kw, :over, quoteof(c.over, ctx)))
    if c.dialect !== default_dialect
        push!(ex.args, Expr(:kw, :dialect, quoteof(c.dialect)))
    end
    if c.columns !== nothing
        push!(ex.args, Expr(:kw, :columns, Expr(:vect, Any[quoteof(col) for col in c.columns]...)))
    end
    ex
end
