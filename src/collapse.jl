# Collapsing SQL subqueries.

collapse(c::SQLClause) =
    convert(SQLClause, collapse(c[]))

collapse(cs::Vector{SQLClause}) =
    SQLClause[collapse(c) for c in cs]

collapse(::Nothing) =
    nothing

collapse(c::AbstractSQLClause) =
    c

collapse(c::AggregateClause) =
    AggregateClause(name = c.name,
                    distinct = c.distinct,
                    args = collapse(c.args),
                    filter = collapse(c.filter),
                    over = collapse(c.over))

collapse(c::AsClause) =
    AsClause(over = collapse(c.over), name = c.name)

collapse(c::CaseClause) =
    CaseClause(args = collapse(c.args))

collapse(c::FromClause) =
    FromClause(over = collapse(c.over))

collapse(c::FunctionClause) =
    FunctionClause(name = c.name, args = collapse(c.args))

collapse(c::GroupClause) =
    GroupClause(over = collapse(c.over), by = collapse(c.by))

collapse(c::JoinClause) =
    JoinClause(over = collapse(c.over),
               joinee = collapse(c.joinee),
               on = collapse(c.on),
               left = c.left, right = c.right, lateral = c.lateral)

collapse(c::KeywordClause) =
    KeywordClause(over = collapse(c.over), name = c.name)

collapse(c::LimitClause) =
    LimitClause(over = collapse(c.over), limit = c.limit, offset = c.offset, with_ties = c.with_ties)

collapse(c::OperatorClause) =
    OperatorClause(name = c.name, args = collapse(c.args))

collapse(c::OrderClause) =
    OrderClause(over = collapse(c.over), by = collapse(c.by))

collapse(c::PartitionClause) =
    PartitionClause(over = collapse(c.over),
                    by = collapse(c.by),
                    order_by = collapse(c.order_by),
                    frame = c.frame)

function collapse(c::SelectClause)
    over′ = collapse(c.over)
    list′ = collapse(c.list)
    d = decompose(over′)
    list′ = substitute(list′, d.subs)
    SelectClause(over = d.tail, top = c.top, distinct = c.distinct, list = unalias(list′))
end

collapse(c::SortClause) =
    SortClause(over = collapse(c.over), value = c.value, nulls = c.nulls)

collapse(c::UnionClause) =
    UnionClause(over = collapse(c.over), all = c.all, list = collapse(c.list))

collapse(c::WhereClause) =
    WhereClause(over = collapse(c.over), condition = collapse(c.condition))

collapse(c::WindowClause) =
    WindowClause(over = collapse(c.over), list = collapse(c.list))

struct Decomposition
    tail::Union{SQLClause, Nothing}
    subs::Dict{Tuple{Symbol, Symbol}, SQLClause}
end

Decomposition(tail) =
    Decomposition(tail, Dict{Tuple{Symbol, Symbol}, SQLClause}())

function decompose(c::SQLClause)
    d = decompose(c[])
    if d === nothing
        d = Decomposition(c)
    end
    d
end

decompose(c::AbstractSQLClause) =
    nothing

decompose(::Nothing) =
    Decomposition(nothing)

function decompose(c::FromClause)
    if @dissect c.over (tail |>
                        SELECT(top = nothing, distinct = false, list = select_list) |>
                        AS(name = alias))
        subs = substitutions(alias, select_list)
        subs !== nothing || return
        return Decomposition(tail, subs)
    end
end

function decompose(c::GroupClause)
    d = decompose(c.over)
    by′ = substitute(c.by, d.subs)
    if @dissect d.tail (tail := nothing || FROM() || JOIN() || WHERE())
        c′ = GROUP(over = tail, by = by′)
        return Decomposition(c′, d.subs)
    else
        return nothing
    end
end

function decompose(c::JoinClause)
    !c.lateral || return nothing
    subs = Dict{Tuple{Symbol, Symbol}, SQLClause}()
    if @dissect c.joinee ((table := (nothing |> ID() |> AS())) |>
                          FROM() |>
                          SELECT(top = nothing, distinct = false, list = select_list) |>
                          AS(name = alias))
        joinee′ = table
        substitutions!(subs, alias, select_list)
    else
        joinee′ = c.joinee
    end
    d = decompose(c.over)
    if @dissect d.tail (FROM() || JOIN())
        over′ = d.tail
        merge!(subs, d.subs)
    else
        over′ = c.over
    end
    on′ = substitute(c.on, subs)
    c′ = JoinClause(over = over′, joinee = joinee′, on = on′, left = c.left, right = c.right, lateral = c.lateral)
    Decomposition(c′, subs)
end

function merge_conditions(c1, c2)
    if @dissect c1 OP(name = :AND, args = args1)
        if @dissect c2 OP(name = :AND, args = args2)
            return OP(:AND, args1..., args2...)
        else
            return OP(:AND, args1..., c2)
        end
    elseif @dissect c2 OP(name = :AND, args = args2)
        return OP(:AND, c1, args2...)
    else
        return OP(:AND, c1, c2)
    end
end

function decompose(c::WhereClause)
    d = decompose(c.over)
    condition′ = substitute(c.condition, d.subs)
    if (@dissect condition′ LIT(val = val)) && val === true
        return d
    end
    if @dissect d.tail (tail := nothing || FROM() || JOIN())
        c′ = WHERE(over = tail, condition = condition′)
        return Decomposition(c′, d.subs)
    elseif @dissect d.tail (tail |> WHERE(condition = tail_condition))
        condition′ = merge_conditions(tail_condition, condition′)
        c′ = WHERE(over = tail, condition = condition′)
        return Decomposition(c′, d.subs)
    elseif (@dissect d.tail (tail := GROUP(by = by))) && !isempty(by)
        c′ = HAVING(over = tail, condition = condition′)
        return Decomposition(c′, d.subs)
    elseif @dissect d.tail (tail |> HAVING(condition = tail_condition))
        condition′ = merge_conditions(tail_condition, condition′)
        c′ = HAVING(over = tail, condition = condition′)
        return Decomposition(c′, d.subs)
    else
        return nothing
    end
end

function decompose(c::WindowClause)
    d = decompose(c.over)
    list′ = substitute(c.list, d.subs)
    if @dissect d.tail (tail := nothing || FROM() || JOIN() || WHERE() || GROUP() || HAVING())
        c′ = WINDOW(over = tail, list = list′)
        return Decomposition(c′, d.subs)
    else
        return nothing
    end
end

unalias(cs::Vector{SQLClause}) =
    SQLClause[unalias(c) for c in cs]

function unalias(c::SQLClause)
    if @dissect c (tail := ID(name = id_name)) |> AS(name = as_name)
        if id_name === as_name
            return tail
        end
    end
    c
end

function substitutions!(subs::Dict{Tuple{Symbol, Symbol}, SQLClause},
                        alias::Symbol, cs::Vector{SQLClause})
    for c in cs
        if @dissect c AS(over = repl, name = name)
            #if @dissect repl AGG()
            #    return nothing
            #end
        elseif @dissect c ID(name = name)
            repl = c
        else
            continue
        end
        subs[(alias, name)] = repl
    end
    subs
end

function substitutions(alias::Symbol, cs::Vector{SQLClause})
    subs = Dict{Tuple{Symbol, Symbol}, SQLClause}()
    substitutions!(subs, alias, cs)
end

function substitute(c::SQLClause, subs::Dict{Tuple{Symbol, Symbol}, SQLClause})
    if @dissect c nothing |> ID(name = base_name) |> ID(name = name)
        key = (base_name, name)
        if key in keys(subs)
            return subs[key]
        end
    end
    convert(SQLClause, substitute(c[], subs))
end

substitute(cs::Vector{SQLClause}, subs::Dict{Tuple{Symbol, Symbol}, SQLClause}) =
    SQLClause[substitute(c, subs) for c in cs]

substitute(::Nothing, subs::Dict{Tuple{Symbol, Symbol}, SQLClause}) =
    nothing

@generated function substitute(c::AbstractSQLClause, subs::Dict{Tuple{Symbol, Symbol}, SQLClause})
    exs = Expr[]
    args = Expr[]
    fs = fieldnames(c)
    for f in fs
        t = fieldtype(c, f)
        if t === SQLClause || t === Union{SQLClause, Nothing} || t === Vector{SQLClause}
            ex = quote
                $(f) = substitute(c.$(f), subs)
            end
            push!(exs, ex)
            arg = Expr(:kw, f, f)
        else
            arg = Expr(:kw, f, :(c.$(f)))
        end
        push!(args, arg)
    end
    if isempty(exs)
        return :(return c)
    end
    push!(exs, :($c($(args...))))
    Expr(:block, exs...)
end

