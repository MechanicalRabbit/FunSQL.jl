# Auxiliary clauses.

# Context holder for the serialize pass.

struct WithContextClause <: AbstractSQLClause
    dialect::SQLDialect
    shape::SQLTable

    WithContextClause(; dialect, shape = SQLTable(name = :_, columns = [])) =
        new(dialect, shape)
end

const WITH_CONTEXT = SQLSyntaxCtor{WithContextClause}(:WITH_CONTEXT)

function PrettyPrinting.quoteof(c::WithContextClause, ctx::QuoteContext)
    ex = Expr(:call, :WITH_CONTEXT)
    if c.dialect !== default_dialect
        push!(ex.args, Expr(:kw, :dialect, quoteof(c.dialect)))
    end
    if c.shape.name !== :_ || !isempty(c.shape.columns) || !isempty(c.shape.metadata)
        push!(ex.args, Expr(:kw, :shape, quoteof(c.shape)))
    end
    ex
end
