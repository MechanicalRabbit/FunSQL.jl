# Auxiliary clauses.

# Context holder for the serialize pass.

struct WithContextClause <: AbstractSQLClause
    dialect::SQLDialect
    columns::Union{Vector{SQLColumn}, Nothing}

    WithContextClause(; dialect, columns = nothing) =
        new(dialect, columns)
end

const WITH_CONTEXT = SQLSyntaxCtor{WithContextClause}

function PrettyPrinting.quoteof(c::WithContextClause, ctx::QuoteContext)
    ex = Expr(:call, :WITH_CONTEXT)
    if c.dialect !== default_dialect
        push!(ex.args, Expr(:kw, :dialect, quoteof(c.dialect)))
    end
    if c.columns !== nothing
        push!(ex.args, Expr(:kw, :columns, Expr(:vect, Any[quoteof(col) for col in c.columns]...)))
    end
    ex
end
