# Rendering SQL.

mutable struct RenderContext <: IO
    dialect::SQLDialect
    io::IOBuffer
    level::Int
    nested::Bool
    vars::Vector{Symbol}

    RenderContext(dialect) =
        new(dialect, IOBuffer(), 0, false, Symbol[])
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
    sql = String(take!(ctx.io))
    SQLStatement(sql = sql, dialect = ctx.dialect, vars = ctx.vars)
end

function render(ctx, name::Symbol)
    if ctx.dialect.name === :sqlserver
        print(ctx, '[', replace(string(name), ']' => "]]"), ']')
    else
        print(ctx, '"', replace(string(name), '"' => "\"\""), '"')
    end
end

function render(ctx, names::Vector{Symbol})
    first = true
    for name in names
        if !first
            print(ctx, ", ")
        else
            first = false
        end
        render(ctx, name)
    end
end

render(ctx, ::Missing) =
    print(ctx, "NULL")

render(ctx, val::Bool) =
    if ctx.dialect.name === :sqlserver
        print(ctx, val ? "(1 = 1)" : "(1 = 0)")
    else
        print(ctx, val ? "TRUE" : "FALSE")
    end

render(ctx, val::Number) =
    print(ctx, val)

render(ctx, val::AbstractString) =
    print(ctx, '\'', replace(val, '\'' => "''"), '\'')

render(ctx, val::Dates.AbstractTime) =
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

function render(ctx, c::AggregateClause)
    if c.filter !== nothing || c.over !== nothing
        print(ctx, '(')
    end
    print(ctx, c.name, '(')
    if c.distinct
        print(ctx, "DISTINCT ")
    end
    render(ctx, c.args)
    print(ctx, ')')
    if c.filter !== nothing
        print(ctx, " FILTER (WHERE ")
        render(ctx, c.filter)
        print(ctx, ')')
    end
    if c.over !== nothing
        print(ctx, " OVER (")
        render(ctx, c.over)
        print(ctx, ')')
    end
    if c.filter !== nothing || c.over !== nothing
        print(ctx, ')')
    end
end

function render(ctx, c::AsClause)
    over = c.over
    if @dissect over PARTITION()
        render(ctx, c.name)
        print(ctx, " AS (")
        render(ctx, over)
        print(ctx, ')')
    elseif over !== nothing
        render(ctx, over)
        print(ctx, " AS ")
        render(ctx, c.name)
    end
end

function render(ctx, c::CaseClause)
    print(ctx, "(CASE")
    nargs = length(c.args)
    for (i, arg) in enumerate(c.args)
        if isodd(i)
            print(ctx, i < nargs ? " WHEN " : " ELSE ")
        else
            print(ctx, " THEN ")
        end
        render(ctx, arg)
    end
    print(ctx, " END)")
end

function render(ctx, c::CTEClause)
    over = c.over
    columns = c.columns
    render(ctx, c.name)
    if columns !== nothing
        print(ctx, " (")
        render(ctx, columns)
        print(ctx, ')')
    end
    if over !== nothing
        print(ctx, " AS ")
        if c.materialized === true
            print(ctx, "MATERIALIZED ")
        elseif c.materialized === false
            print(ctx, "NOT MATERIALIZED ")
        end
        nested = ctx.nested
        ctx.nested = true
        render(ctx, over)
        ctx.nested = nested
    end
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

function render(ctx, c::GroupClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    !isempty(c.by) || return
    newline(ctx)
    print(ctx, "GROUP BY ")
    render(ctx, c.by)
end

function render(ctx, c::HavingClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    newline(ctx)
    print(ctx, "HAVING ")
    render(ctx, c.condition)
end

function render(ctx, c::IdentifierClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
        print(ctx, '.')
    end
    render(ctx, c.name)
end

function render(ctx, c::JoinClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    newline(ctx)
    cross = !c.left && !c.right && @dissect c.on LIT(val = true)
    if cross
        print(ctx, "CROSS JOIN ")
    elseif c.left && c.right
        print(ctx, "FULL JOIN ")
    elseif c.left
        print(ctx, "LEFT JOIN ")
    elseif c.right
        print(ctx, "RIGHT JOIN ")
    else
        print(ctx, "JOIN ")
    end
    if c.lateral
        print(ctx, "LATERAL ")
    end
    render(ctx, c.joinee)
    if !cross
        print(ctx, " ON ")
        render(ctx, c.on)
    end
end

function render(ctx, c::KeywordClause)
    print(ctx, c.name)
    over = c.over
    if over !== nothing
        print(ctx, ' ')
        render(ctx, over)
    end
end

function render(ctx, c::LimitClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    start = c.offset
    count = c.limit
    start !== nothing || count !== nothing || return
    if ctx.dialect.name === :mysql
        newline(ctx)
        print(ctx, "LIMIT ")
        if start !== nothing
            print(ctx, start, ", ")
        end
        print(ctx, count !== nothing ? count : "18446744073709551615")
    elseif ctx.dialect.name === :sqlite
        newline(ctx)
        print(ctx, "LIMIT ", count !== nothing ? count : -1)
        if start !== nothing
            newline(ctx)
            print(ctx, "OFFSET ", start)
        end
    else
        if start !== nothing
            newline(ctx)
            print(ctx, "OFFSET ", start, start == 1 ? " ROW" : " ROWS")
        end
        if count !== nothing
            newline(ctx)
            print(ctx, start === nothing ? "FETCH FIRST " : "FETCH NEXT ",
                       count, count == 1 ? " ROW" : " ROWS",
                       c.with_ties ? " WITH TIES" : " ONLY")
        end
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

function render(ctx, c::OrderClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    !isempty(c.by) || return
    newline(ctx)
    print(ctx, "ORDER BY ")
    render(ctx, c.by)
end

function render(ctx, m::FrameMode)
    if m == FRAME_MODE.RANGE
        print(ctx, "RANGE")
    elseif m == FRAME_MODE.ROWS
        print(ctx, "ROWS")
    elseif m == FRAME_MODE.GROUPS
        print(ctx, "GROUPS")
    else
        throw(DomainError(m))
    end
end

function render(ctx, e::FrameExclusion)
    if e == FRAME_EXCLUSION.NO_OTHERS
        print(ctx, "EXCLUDE NO OTHERS")
    elseif e == FRAME_EXCLUSION.CURRENT_ROW
        print(ctx, "EXCLUDE CURRENT ROW")
    elseif e == FRAME_EXCLUSION.GROUP
        print(ctx, "EXCLUDE GROUP")
    elseif e == FRAME_EXCLUSION.TIES
        print(ctx, "EXCLUDE TIES")
    else
        throw(DomainError(e))
    end
end

function render_frame_endpoint(ctx, val)
    if iszero(val)
        print(ctx, "CURRENT ROW")
    else
        pos = val > zero(val)
        inf = isinf(val)
        if pos && inf
            print(ctx, "UNBOUNDED FOLLOWING")
        elseif pos
            render(ctx, val)
            print(ctx, " FOLLOWING")
        elseif !inf
            render(ctx, - val)
            print(ctx, " PRECEDING")
        else
            print(ctx, "UNBOUNDED PRECEDING")
        end
    end
end

function render(ctx, f::PartitionFrame)
    render(ctx, f.mode)
    print(ctx, ' ')
    if f.finish === nothing
        render_frame_endpoint(ctx, something(f.start, -Inf))
    else
        print(ctx, "BETWEEN ")
        render_frame_endpoint(ctx, something(f.start, -Inf))
        print(ctx, " AND ")
        render_frame_endpoint(ctx, f.finish)
    end
    if f.exclude !== nothing
        print(ctx, ' ')
        render(ctx, f.exclude)
    end
end

function render(ctx, c::PartitionClause)
    need_space = false
    if c.over !== nothing
        render(ctx, c.over)
        need_space = true
    end
    if !isempty(c.by)
        if need_space
            print(ctx, ' ')
        end
        print(ctx, "PARTITION BY ")
        render(ctx, c.by)
        need_space = true
    end
    if !isempty(c.order_by)
        if need_space
            print(ctx, ' ')
        end
        print(ctx, "ORDER BY ")
        render(ctx, c.order_by)
        need_space = true
    end
    if c.frame !== nothing
        if need_space
            print(ctx, ' ')
        end
        render(ctx, c.frame)
        need_space = true
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
    top = c.top
    if top !== nothing
        print(ctx, " TOP ", top.limit)
        if top.with_ties
            print(ctx, " WITH TIES")
        end
    end
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

function render(ctx, c::SortClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    if c.value == VALUE_ORDER.ASC
        print(ctx, " ASC")
    elseif c.value == VALUE_ORDER.DESC
        print(ctx, " DESC")
    end
    if c.nulls == NULLS_ORDER.NULLS_FIRST
        print(ctx, " NULLS FIRST")
    elseif c.nulls == NULLS_ORDER.NULLS_LAST
        print(ctx, " NULLS LAST")
    end
end

function render(ctx, c::UnionClause)
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, '(')
        newline(ctx)
    end
    ctx.nested = false
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    for l in c.list
        newline(ctx)
        print(ctx, "UNION")
        if c.all
            print(ctx, " ALL")
        end
        newline(ctx)
        render(ctx, l)
    end
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ')')
    end
end

function render(ctx, c::VariableClause)
    style = ctx.dialect.variable_style
    prefix = ctx.dialect.variable_prefix
    pos = nothing
    if style != VARIABLE_STYLE.POSITIONAL
        pos = findfirst(==(c.name), ctx.vars)
    end
    if pos === nothing
        push!(ctx.vars, c.name)
        pos = length(ctx.vars)
    end
    print(ctx, prefix)
    if style == VARIABLE_STYLE.NAMED
        print(ctx, c.name)
    elseif style == VARIABLE_STYLE.NUMBERED
        print(ctx, pos)
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

function render(ctx, c::WindowClause)
    over = c.over
    if over !== nothing
        render(ctx, over)
    end
    !isempty(c.list) || return
    newline(ctx)
    print(ctx, "WINDOW ")
    render(ctx, c.list)
end

function render(ctx, c::WithClause)
    if !isempty(c.list)
        print(ctx, "WITH ")
        if c.recursive
            print(ctx, "RECURSIVE ")
        end
        first = true
        for l in c.list
            if !first
                print(ctx, ",")
                newline(ctx)
            else
                first = false
            end
            render(ctx, l)
        end
        newline(ctx)
    end
    if c.over !== nothing
        render(ctx, c.over)
    end
end

