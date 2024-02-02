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

function serialize(c::SQLClause)
    @dissect(c, WITH_CONTEXT(over = c′, dialect = dialect)) || throw(IllFormedError())
    ctx = SerializeContext(dialect)
    serialize!(c′, ctx)
    raw = String(take!(ctx.io))
    SQLString(raw, vars = ctx.vars)
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
    if ctx.dialect.is_backslash_literal
        if '\'' in val
            val = replace(val, '\'' => "''")
        end
    else
        if '\\' in val || '\'' in val
            val = replace(replace(val, '\\' => "\\\\"), '\'' => "\\'")
        end
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
            if sep === nothing
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
                else
                    print(ctx, ' ', sep)
                end
                newline(ctx)
            else
                first = false
            end
            serialize!(c, ctx)
        end
        ctx.level -= 1
    end
end

macro serialize!(tmpl, args, ctx)
    tmpl isa String || error("invalid template $(repr(tmpl))")
    args = esc(args)
    ctx = esc(ctx)
    contains_only_symbols = true
    starts_with_space = false
    ends_with_space = false
    placeholders = Int[]
    maybe_literal_qmark = false
    next = iterate(tmpl)
    i = 1
    while next !== nothing
        ch, i′ = next
        contains_only_symbols =
            contains_only_symbols &&
            ch in ('!', '#', '$', '%', '&', '*', '+', '-', '/', ':',
                   '<', '=', '>', '?', '@', '\\', '^', '|', '~')
        starts_with_space = starts_with_space || i == 1 && ch == ' '
        ends_with_space = ch == ' '
        if ch == '?' && maybe_literal_qmark
            pop!(placeholders)
            maybe_literal_qmark = false
        elseif ch == '?'
            push!(placeholders, i)
            maybe_literal_qmark = true
        else
            maybe_literal_qmark = false
        end
        ends_with_space = ch == ' '
        next = iterate(tmpl, i′)
        i = i′
    end
    if isempty(placeholders)
        if starts_with_space || ends_with_space
            tmpl = string(strip(tmpl))
        end
        if '?' in tmpl
            tmpl = replace(tmpl, "??" => '?')
        end
        if isempty(tmpl)
            # Comma-separated list of arguments.
            return :(serialize_function!("", $args, $ctx))
        elseif contains_only_symbols || starts_with_space || ends_with_space
            # An operator.
            if starts_with_space && !ends_with_space
                return :(serialize_postfix_operator!($tmpl, $args, $ctx))
            else
                return :(serialize_operator!($tmpl, $args, $ctx))
            end
        else
            # A function.
            return :(serialize_function!($tmpl, $args, $ctx))
        end
    else
        # A template with placeholders.
        chunks = String[]
        push!(placeholders, lastindex(tmpl) + 1)
        i = 0
        for k in eachindex(placeholders)
            j = placeholders[k]
            chunk = tmpl[i+1:j-1]
            if '?' in chunk
                chunk = replace(chunk, "??" => '?')
            end
            push!(chunks, chunk)
            i = j
        end
        return :(serialize_template!($(tuple(chunks...)), $args, $ctx))
    end
end

function serialize_operator!(op::String, args::Vector{SQLClause}, ctx)
    if isempty(args)
        print(ctx, op)
    elseif length(args) == 1
        print(ctx, '(', op, ' ')
        serialize!(args[1], ctx)
        print(ctx, ')')
    else
        print(ctx, '(')
        serialize!(args, ctx, sep = op)
        print(ctx, ')')
    end
end

function serialize_postfix_operator!(op::String, args::Vector{SQLClause}, ctx)
    if isempty(args)
        print(ctx, op)
    elseif length(args) == 1
        print(ctx, '(')
        serialize!(args[1], ctx)
        print(ctx, ' ', op, ')')
    else
        print(ctx, '(')
        serialize!(args, ctx, sep = op)
        print(ctx, ')')
    end
end

function serialize_function!(name::String, args::Vector{SQLClause}, ctx)
    print(ctx, name, '(')
    serialize!(args, ctx)
    print(ctx, ')')
end

function serialize_template!(@nospecialize(chunks::Tuple{Vararg{String}}), args::Vector{SQLClause}, ctx)
    for k = 1:lastindex(chunks)-1
        print(ctx, chunks[k])
        if k <= length(args)
            serialize!(args[k], ctx)
        end
    end
    print(ctx, chunks[end])
end

@generated serialize!(::Val{N}, args::Vector{SQLClause}, ctx) where {N} =
    :(@serialize! $(string(N)) args ctx)

arity(name::Symbol) =
    arity(Val(name))

@generated function arity(::Val{N}) where {N}
    tmpl = string(N)
    arity = 0
    maybe_literal_qmark = false
    next = iterate(tmpl)
    while next !== nothing
        ch, i′ = next
        if ch == '?' && maybe_literal_qmark
            arity -= 1
            maybe_literal_qmark = false
        elseif ch == '?'
            arity += 1
            maybe_literal_qmark = true
        else
            maybe_literal_qmark = false
        end
        next = iterate(tmpl, i′)
    end
    arity > 0 ? :($arity:$arity) : 0
end

for (name, op, default) in ((:and, "AND", true),
                            (:or, "OR", false))
    @eval begin
        function serialize!(::Val{$(QuoteNode(name))}, args::Vector{SQLClause}, ctx)
            if isempty(args)
                serialize!($default, ctx)
            elseif length(args) == 1
                serialize!(args[1], ctx)
            else
                print(ctx, '(')
                serialize!(args, ctx, sep = $op)
                print(ctx, ')')
            end
        end

        arity(::Val{$(QuoteNode(name))}) = 0
    end
end

for (name, op, default) in ((:in, "IN", false),
                            (:not_in, "NOT IN", true))
    @eval begin
        function serialize!(::Val{$(QuoteNode(name))}, args::Vector{SQLClause}, ctx)
            if length(args) <= 1
                serialize!($default, ctx)
            else
                print(ctx, '(')
                serialize!(args[1], ctx)
                print(ctx, ' ', $op, ' ')
                if length(args) == 2 && @dissect(args[2], SELECT() || UNION())
                    serialize!(args[2], ctx)
                else
                    print(ctx, '(')
                    serialize!(args[2:end], ctx)
                    print(ctx, ')')
                end
                print(ctx, ')')
            end
        end

        arity(::Val{$(QuoteNode(name))}) = 1
    end
end

serialize!(::Val{Symbol("not in")}, args::Vector{SQLClause}, ctx) =
    serialize!(Val(:not_in), args, ctx)

serialize!(::Val{:not}, args::Vector{SQLClause}, ctx) =
    @serialize! "NOT " args ctx

arity(::Val{:not}) = 1:1

serialize!(::Val{:exists}, args::Vector{SQLClause}, ctx) =
    @serialize! "EXISTS " args ctx

arity(::Val{:exists}) = 1:1

serialize!(::Val{:not_exists}, args::Vector{SQLClause}, ctx) =
    @serialize! "NOT EXISTS " args ctx

arity(::Val{:not_exists}) = 1:1

serialize!(::Val{:is_null}, args::Vector{SQLClause}, ctx) =
    @serialize! " IS NULL" args ctx

arity(::Val{:is_null}) = 1:1

serialize!(::Val{Symbol("is null")}, args::Vector{SQLClause}, ctx) =
    serialize!(Val(:is_null), args, ctx)

serialize!(::Val{:is_not_null}, args::Vector{SQLClause}, ctx) =
    @serialize! " IS NOT NULL" args ctx

arity(::Val{:is_not_null}) = 1:1

serialize!(::Val{Symbol("is not null")}, args::Vector{SQLClause}, ctx) =
    serialize!(Val(:is_not_null), args, ctx)

serialize!(::Val{:like}, args::Vector{SQLClause}, ctx) =
    @serialize! " LIKE " args ctx

arity(::Val{:like}) = 2:2

serialize!(::Val{:not_like}, args::Vector{SQLClause}, ctx) =
    @serialize! " NOT LIKE " args ctx

arity(::Val{:not_like}) = 2:2

function serialize!(::Val{:count}, args::Vector{SQLClause}, ctx)
    print(ctx, "count(")
    if isempty(args)
        print(ctx, "*")
    else
        serialize!(args, ctx)
    end
    print(ctx, ")")
end

arity(::Val{:count}) = 0:1

function serialize!(::Val{:count_distinct}, args::Vector{SQLClause}, ctx)
    print(ctx, "count(DISTINCT ")
    if isempty(args)
        print(ctx, "*")
    else
        serialize!(args, ctx)
    end
    print(ctx, ")")
end

arity(::Val{:count_distinct}) = 0:1

function serialize!(::Val{:cast}, args::Vector{SQLClause}, ctx)
    if length(args) == 2 && @dissect(args[2], LIT(val = t)) && t isa AbstractString
        print(ctx, "CAST(")
        serialize!(args[1], ctx)
        print(ctx, " AS ", t, ')')
    else
        @serialize! "cast" args ctx
    end
end

arity(::Val{:cast}) = 2:2

function serialize!(::Val{:concat}, args::Vector{SQLClause}, ctx)
    concat_operator = ctx.dialect.concat_operator
    if concat_operator !== nothing
        serialize_operator!(string(concat_operator), args, ctx)
    else
        serialize_function!("concat", args, ctx)
    end
end

arity(::Val{:concat}) = 2

function serialize!(::Val{:extract}, args::Vector{SQLClause}, ctx)
    if length(args) == 2 && @dissect(args[1], LIT(val = f)) && f isa AbstractString
        print(ctx, "EXTRACT(", f, " FROM ")
        serialize!(args[2], ctx)
        print(ctx, ')')
    else
        @serialize! "extract" args ctx
    end
end

arity(::Val{:extract}) = 2:2

for (name, op) in ((:between, " BETWEEN "),
                   (:not_between, " NOT BETWEEN "))
    @eval begin
        function serialize!(::Val{$(QuoteNode(name))}, args::Vector{SQLClause}, ctx)
            if length(args) == 3
                print(ctx, '(')
                serialize!(args[1], ctx)
                print(ctx, $op)
                serialize!(args[2], ctx)
                print(ctx, " AND ")
                serialize!(args[3], ctx)
                print(ctx, ')')
            else
                @serialize! $(string(name)) args ctx
            end
        end

        arity(::Val{$(QuoteNode(name))}) = 3:3
    end
end

serialize!(::Val{Symbol("not between")}, args::Vector{SQLClause}, ctx) =
    serialize!(Val(:not_between), args, ctx)

for (name, op) in ((:current_date, "CURRENT_DATE"),
                   (:current_timestamp, "CURRENT_TIMESTAMP"))
    @eval begin
        function serialize!(::Val{$(QuoteNode(name))}, args::Vector{SQLClause}, ctx)
            if isempty(args)
                print(ctx, $op)
            else
                print(ctx, $op, '(')
                serialize!(args, ctx)
                print(ctx, ')')
            end
        end

        arity(::Val{$(QuoteNode(name))}) = 0
    end
end

function serialize!(::Val{:case}, args::Vector{SQLClause}, ctx)
    print(ctx, "(CASE")
    nargs = length(args)
    for (i, arg) in enumerate(args)
        if isodd(i)
            print(ctx, i < nargs ? " WHEN " : " ELSE ")
        else
            print(ctx, " THEN ")
        end
        serialize!(arg, ctx)
    end
    print(ctx, " END)")
end

arity(::Val{:case}) = 2

function serialize!(c::AggregateClause, ctx)
    if c.filter !== nothing || c.over !== nothing
        print(ctx, '(')
    end
    serialize!(Val(c.name), c.args, ctx)
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
    serialize!(Val(c.name), c.args, ctx)
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
    if @dissect(c.condition, FUN(name = :and, args = args)) && length(args) >= 2
        serialize_lines!(args, ctx, sep = "AND")
    elseif @dissect(c.condition, FUN(name = :or, args = args)) && length(args) >= 2
        serialize_lines!(args, ctx, sep = "OR")
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
    elseif ctx.dialect.limit_style == LIMIT_STYLE.POSTGRESQL
        if count !== nothing
            newline(ctx)
            print(ctx, "LIMIT ", count)
        end
        if start !== nothing
            newline(ctx)
            print(ctx, "OFFSET ", start)
        end
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
    over = c.over
    limit = nothing
    with_ties = false
    offset_0_rows = false
    top = c.top
    if top !== nothing
        limit = top.limit
        with_ties = top.with_ties
    elseif ctx.dialect.limit_style === LIMIT_STYLE.SQLSERVER
        if @dissect(over, limit_over |> LIMIT(offset = nothing, limit = limit, with_ties = with_ties))
            over = limit_over
        elseif nested && @dissect(over, ORDER())
            offset_0_rows = true
        end
    end
    print(ctx, "SELECT")
    if limit !== nothing
        print(ctx, " TOP ", limit)
        if with_ties
            print(ctx, " WITH TIES")
        end
    end
    if c.distinct
        print(ctx, " DISTINCT")
    end
    serialize_lines!(c.args, ctx)
    if over !== nothing
        serialize!(over, ctx)
    end
    if offset_0_rows
        newline(ctx)
        print(ctx, "OFFSET 0 ROWS")
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

function serialize!(c::ValuesClause, ctx)
    nested = ctx.nested
    if nested
        ctx.level += 1
        print(ctx, '(')
        newline(ctx)
    end
    ctx.nested = true
    l = length(c.rows)
    print(ctx, "VALUES")
    if l == 1
        print(ctx, ' ')
    elseif l > 1
        ctx.level += 1
        newline(ctx)
    end
    first_row = true
    row_constructor = ctx.dialect.values_row_constructor
    for row in c.rows
        if !first_row
            print(ctx, ',')
            newline(ctx)
        else
            first_row = false
        end
        if row isa Union{Vector, Tuple, NamedTuple}
            first_val = true
            if row_constructor !== nothing
                print(ctx, row_constructor)
            end
            print(ctx, '(')
            for val in row
                if !first_val
                    print(ctx, ", ")
                else
                    first_val = false
                end
                serialize!(val, ctx)
            end
            print(ctx, ')')
        else
            serialize!(row, ctx)
        end
    end
    if l > 1
        ctx.level -= 1
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
    if @dissect(c.condition, FUN(name = :and, args = args)) && length(args) >= 2
        serialize_lines!(args, ctx, sep = "AND")
    elseif @dissect(c.condition, FUN(name = :or, args = args)) && length(args) >= 2
        serialize_lines!(args, ctx, sep = "OR")
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
