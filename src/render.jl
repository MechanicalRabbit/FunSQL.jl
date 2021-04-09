# Rendering SQL.

mutable struct RenderContext <: IO
    dialect::SQLDialect
    io::IOBuffer
    level::Int
    nested::Bool

    RenderContext(dialect) =
        new(dialect, IOBuffer(), 0, false)
end

Base.write(ctx::RenderContext, octet::UInt8) =
    write(ctx.io, octet)

Base.unsafe_write(ctx::RenderContext, input::Ptr{UInt8}, nbytes::UInt) =
    unsafe_write(ctx.io, input, nbytes)

function newline(ctx::RenderContext)
    print(ctx, "\n")
    for k = 1:ctx.level
        print(ctx, "  ")
    end
end

function render(c::AbstractSQLClause; dialect = :default)
    ctx = RenderContext(dialect)
    render(ctx, convert(SQLClause, c))
    String(take!(ctx.io))
end

render(ctx, name::Symbol) =
    print(ctx, '"', replace(string(name), '"' => "\"\""), '"')

render(ctx, ::Missing) =
    print(ctx, "NULL")

render(ctx, val::Bool) =
    print(ctx, val ? "TRUE" : "FALSE")

render(ctx, val::Number) =
    print(ctx, val)

render(ctx, val::AbstractString) =
    print(ctx, '\'', replace(val, '\'' => "''"), '\'')

render(ctx, val::Dates.Date) =
    print(ctx, '\'', val, '\'')

function render(ctx, c::SQLClause)
    render(ctx, c[])
    nothing
end

function render(ctx, cs::AbstractVector{SQLClause}, sep = nothing)
    first = true
    for c in cs
        if !first
            if @dissect c KW()
                print(ctx, ' ')
            elseif sep === nothing
                print(ctx, ", ")
            else
                print(ctx, ' ', sep, ' ')
            end
        else
            first = false
        end
        render(ctx, c)
    end
end

function render(ctx, c::AsClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
        print(ctx, " AS ")
    end
    render(ctx, c.name)
end

function render(ctx, c::FromClause)
    newline(ctx)
    print(ctx, "FROM")
    over = c.over
    if over !== nothing
        print(ctx, ' ')
        render(ctx, over)
    end
end

function render(ctx, c::FunctionClause)
    print(ctx, c.name, '(')
    render(ctx, c.args)
    print(ctx, ')')
end

function render(ctx, c::IdentifierClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
        print(ctx, '.')
    end
    render(ctx, c.name)
end

function render(ctx, c::KeywordClause)
    print(ctx, c.name)
    over = c.over
    if over !== nothing
        print(ctx, ' ')
        render(ctx, over)
    end
end

render(ctx, c::LiteralClause) =
    render(ctx, c.val)

function render(ctx, c::OperatorClause)
    if isempty(c.args)
        print(ctx, c.name)
    elseif length(c.args) == 1
        print(ctx, '(', c.name, ' ')
        render(ctx, c.args[1])
        print(ctx, ')')
    else
        print(ctx, '(')
        render(ctx, c.args, c.name)
        print(ctx, ')')
    end
end

function render(ctx, c::SelectClause)
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, '(')
        newline(ctx)
    end
    ctx.nested = true
    print(ctx, "SELECT")
    if c.distinct
        print(ctx, " DISTINCT")
    end
    if !isempty(c.list)
        print(ctx, ' ')
        render(ctx, c.list)
    end
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ')')
    end
end

function render(ctx, c::WhereClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    newline(ctx)
    print(ctx, "WHERE ")
    render(ctx, c.condition)
end

