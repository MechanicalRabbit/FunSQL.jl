# SQL Serialization.

mutable struct SerializeContext <: IO
    dialect::SQLDialect
    io::IOBuffer
    level::Int
    nested::Bool
    vars::Vector{Symbol}

    SerializeContext(dialect) =
        new(dialect, IOBuffer(), 0, false, Symbol[])
end

Base.write(ctx::SerializeContext, octet::UInt8) =
    write(ctx.io, octet)

Base.unsafe_write(ctx::SerializeContext, input::Ptr{UInt8}, nbytes::UInt) =
    unsafe_write(ctx.io, input, nbytes)

function newline(ctx::SerializeContext)
    print(ctx, "\n")
    for k = 1:ctx.level
        print(ctx, "  ")
    end
end

function serialize!(name::Symbol, ctx)
    s = string(name)
    lq, rq = ctx.dialect.identifier_quotes
    if rq in s
        s = replace(s, rq => rq * rq)
    end
    print(ctx, lq, s, rq)
end

function serialize!(names::Vector{Symbol}, ctx)
    first = true
    for name in names
        if !first
            print(ctx, ", ")
        else
            first = false
        end
        serialize!(name, ctx)
    end
end

serialize!(::Missing, ctx) =
    print(ctx, "NULL")

serialize!(val::Bool, ctx) =
    if ctx.dialect.has_boolean_literals
        print(ctx, val ? "TRUE" : "FALSE")
    else
        print(ctx, val ? "(1 = 1)" : "(1 = 0)")
    end

serialize!(val::Number, ctx) =
    print(ctx, val)

function serialize!(val::AbstractString, ctx)
    if '\'' in val
        val = replace(val, '\'' => "''")
    end
    print(ctx, '\'', val, '\'')
end

serialize!(val::Dates.AbstractTime, ctx) =
    print(ctx, '\'', val, '\'')

function serialize!(c::SQLClause, ctx::SerializeContext)
    serialize!(c[], ctx)
    nothing
end

function serialize!(cs::AbstractVector{SQLClause}, ctx; sep = nothing)
    first = true
    for c in cs
        if !first
            if @dissect(c, KW())
                print(ctx, ' ')
            elseif sep === nothing
                print(ctx, ", ")
            else
                print(ctx, ' ', sep, ' ')
            end
        else
            first = false
        end
        serialize!(c, ctx)
    end
end

function serialize_lines!(cs::AbstractVector{SQLClause}, ctx; sep = nothing)
    !isempty(cs) || return
    if length(cs) == 1
        print(ctx, ' ')
        serialize!(cs[1], ctx)
    else
        ctx.level += 1
        newline(ctx)
        first = true
        for c in cs
            if !first
                if sep === nothing
                    print(ctx, ',')
                    newline(ctx)
                else
                    print(ctx, ' ', sep)
                    newline(ctx)
                end
            else
                first = false
            end
            serialize!(c, ctx)
        end
        ctx.level -= 1
    end
end

function serialize!(c::AggregateClause, ctx)
    if c.filter !== nothing || c.over !== nothing
        print(ctx, '(')
    end
    print(ctx, c.name, '(')
    if c.distinct
        print(ctx, "DISTINCT ")
    end
    serialize!(c.args, ctx)
    print(ctx, ')')
    if c.filter !== nothing
        print(ctx, " FILTER (WHERE ")
        serialize!(c.filter, ctx)
        print(ctx, ')')
    end
    if c.over !== nothing
        print(ctx, " OVER (")
        serialize!(c.over, ctx)
        print(ctx, ')')
    end
    if c.filter !== nothing || c.over !== nothing
        print(ctx, ')')
    end
end

function serialize!(c::AsClause, ctx)
    over = c.over
    columns = c.columns
    if @dissect(over, PARTITION())
        @assert columns === nothing
        serialize!(c.name, ctx)
        print(ctx, " AS (")
        serialize!(over, ctx)
        print(ctx, ')')
    elseif over !== nothing
        serialize!(over, ctx)
        print(ctx, " AS ")
        serialize!(c.name, ctx)
        if columns !== nothing
            print(ctx, " (")
            serialize!(columns, ctx)
            print(ctx, ')')
        end
    end
end

function serialize!(c::CaseClause, ctx)
    print(ctx, "(CASE")
    nargs = length(c.args)
    for (i, arg) in enumerate(c.args)
        if isodd(i)
            print(ctx, i < nargs ? " WHEN " : " ELSE ")
        else
            print(ctx, " THEN ")
        end
        serialize!(arg, ctx)
    end
    print(ctx, " END)")
end

function serialize!(c::FromClause, ctx)
    newline(ctx)
    print(ctx, "FROM")
    over = c.over
    if over !== nothing
        print(ctx, ' ')
        serialize!(over, ctx)
    end
end

function serialize!(c::FunctionClause, ctx)
    print(ctx, c.name, '(')
    serialize!(c.args, ctx)
    print(ctx, ')')
end

function serialize!(c::GroupClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    !isempty(c.by) || return
    newline(ctx)
    print(ctx, "GROUP BY")
    serialize_lines!(c.by, ctx)
end

function serialize!(c::HavingClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    newline(ctx)
    print(ctx, "HAVING")
    if @dissect(c.condition, OP(name = :AND, args = args)) && length(args) >= 2
        serialize_lines!(args, ctx, sep = "AND")
    else
        print(ctx, ' ')
        serialize!(c.condition, ctx)
    end
end

function serialize!(c::IdentifierClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
        print(ctx, '.')
    end
    serialize!(c.name, ctx)
end

function serialize!(c::JoinClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    newline(ctx)
    cross = !c.left && !c.right && @dissect(c.on, LIT(val = true))
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
    serialize!(c.joinee, ctx)
    if !cross
        print(ctx, " ON ")
        serialize!(c.on, ctx)
    end
end

function serialize!(c::KeywordClause, ctx)
    print(ctx, c.name)
    over = c.over
    if over !== nothing
        print(ctx, ' ')
        serialize!(over, ctx)
    end
end

function serialize!(c::LimitClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    start = c.offset
    count = c.limit
    start !== nothing || count !== nothing || return
    if ctx.dialect.limit_style === LIMIT_STYLE.MYSQL
        newline(ctx)
        print(ctx, "LIMIT ")
        if start !== nothing
            print(ctx, start, ", ")
        end
        print(ctx, count !== nothing ? count : "18446744073709551615")
    elseif ctx.dialect.limit_style === LIMIT_STYLE.SQLITE
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

serialize!(c::LiteralClause, ctx) =
    serialize!(c.val, ctx)

function serialize!(c::NoteClause, ctx)
    over = c.over
    if over === nothing
        print(ctx, c.text)
    elseif c.postfix
        serialize!(over, ctx)
        print(ctx, ' ', c.text)
    else
        print(ctx, c.text, ' ')
        serialize!(over, ctx)
    end
end

function serialize!(c::OperatorClause, ctx)
    if isempty(c.args)
        print(ctx, c.name)
    elseif length(c.args) == 1
        print(ctx, '(', c.name, ' ')
        serialize!(c.args[1], ctx)
        print(ctx, ')')
    else
        print(ctx, '(')
        serialize!(c.args, ctx, sep = c.name)
        print(ctx, ')')
    end
end

function serialize!(c::OrderClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    !isempty(c.by) || return
    newline(ctx)
    print(ctx, "ORDER BY")
    serialize_lines!(c.by, ctx)
end

function serialize!(m::FrameMode, ctx)
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

function serialize!(e::FrameExclusion, ctx)
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

function serialize_frame_endpoint!(val, ctx)
    if iszero(val)
        print(ctx, "CURRENT ROW")
    else
        pos = val > zero(val)
        inf = isinf(val)
        if pos && inf
            print(ctx, "UNBOUNDED FOLLOWING")
        elseif pos
            serialize!(val, ctx)
            print(ctx, " FOLLOWING")
        elseif !inf
            serialize!(- val, ctx)
            print(ctx, " PRECEDING")
        else
            print(ctx, "UNBOUNDED PRECEDING")
        end
    end
end

function serialize!(f::PartitionFrame, ctx)
    serialize!(f.mode, ctx)
    print(ctx, ' ')
    if f.finish === nothing
        serialize_frame_endpoint!(something(f.start, -Inf), ctx)
    else
        print(ctx, "BETWEEN ")
        serialize_frame_endpoint!(something(f.start, -Inf), ctx)
        print(ctx, " AND ")
        serialize_frame_endpoint!(f.finish, ctx)
    end
    if f.exclude !== nothing
        print(ctx, ' ')
        serialize!(f.exclude, ctx)
    end
end

function serialize!(c::PartitionClause, ctx)
    need_space = false
    if c.over !== nothing
        serialize!(c.over, ctx)
        need_space = true
    end
    if !isempty(c.by)
        if need_space
            print(ctx, ' ')
        end
        print(ctx, "PARTITION BY ")
        serialize!(c.by, ctx)
        need_space = true
    end
    if !isempty(c.order_by)
        if need_space
            print(ctx, ' ')
        end
        print(ctx, "ORDER BY ")
        serialize!(c.order_by, ctx)
        need_space = true
    end
    if c.frame !== nothing
        if need_space
            print(ctx, ' ')
        end
        serialize!(c.frame, ctx)
        need_space = true
    end
end

function serialize!(c::SelectClause, ctx)
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
    serialize_lines!(c.args, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ')')
    end
end

function serialize!(c::SortClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
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

function serialize!(c::UnionClause, ctx)
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, '(')
        newline(ctx)
    end
    ctx.nested = false
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    for arg in c.args
        newline(ctx)
        print(ctx, "UNION")
        if c.all
            print(ctx, " ALL")
        end
        newline(ctx)
        serialize!(arg, ctx)
    end
    ctx.nested = nested
    if nested
        ctx.level -= 1
        newline(ctx)
        print(ctx, ')')
    end
end

function serialize!(c::VariableClause, ctx)
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

function serialize!(c::WhereClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    newline(ctx)
    print(ctx, "WHERE")
    if @dissect(c.condition, OP(name = :AND, args = args)) && length(args) >= 2
        serialize_lines!(args, ctx, sep = "AND")
    else
        print(ctx, ' ')
        serialize!(c.condition, ctx)
    end
end

function serialize!(c::WindowClause, ctx)
    over = c.over
    if over !== nothing
        serialize!(over, ctx)
    end
    !isempty(c.args) || return
    newline(ctx)
    print(ctx, "WINDOW")
    serialize_lines!(c.args, ctx)
end

function serialize!(c::WithClause, ctx)
    if !isempty(c.args)
        print(ctx, "WITH ")
        if c.recursive && ctx.dialect.has_recursive_annotation
            print(ctx, "RECURSIVE ")
        end
        first = true
        for arg in c.args
            if !first
                print(ctx, ",")
                newline(ctx)
            else
                first = false
            end
            if @dissect(arg, AS(name = name, columns = columns, over = arg))
                serialize!(name, ctx)
                if columns !== nothing
                    print(ctx, " (")
                    serialize!(columns, ctx)
                    print(ctx, ')')
                end
                print(ctx, " AS ")
            end
            nested = ctx.nested
            ctx.nested = true
            serialize!(arg, ctx)
            ctx.nested = nested
        end
        newline(ctx)
    end
    if c.over !== nothing
        serialize!(c.over, ctx)
    end
end

