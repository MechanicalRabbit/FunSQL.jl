# Auxiliary clauses.

# Context holder for the serialize pass.

struct WithContextClause <: AbstractSQLClause
    dialect::SQLDialect
    table::Union{SQLTable, Nothing}

    WithContextClause(; dialect, table = nothing) =
        new(dialect, table)
end

const WITH_CONTEXT = SQLSyntaxCtor{WithContextClause}(:WITH_CONTEXT)

function PrettyPrinting.quoteof(c::WithContextClause, ctx::QuoteContext)
    ex = Expr(:call, :WITH_CONTEXT)
    if c.dialect !== default_dialect
        push!(ex.args, Expr(:kw, :dialect, quoteof(c.dialect)))
    end
    if c.table !== nothing
        push!(ex.args, Expr(:kw, :table, quoteof(c.table)))
    end
    ex
end
