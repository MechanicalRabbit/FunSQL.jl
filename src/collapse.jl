# Collapsing SQL subqueries.

collapse(c::SQLClause) =
    convert(SQLClause, collapse(c[]))

collapse(cs::Vector{SQLClause}) =
    SQLClause[collapse(c) for c in cs]

collapse(::Nothing) =
    nothing

collapse(c::AbstractSQLClause) =
    c

collapse(c::AsClause) =
    AsClause(over = collapse(c.over), name = c.name)

collapse(c::FromClause) =
    FromClause(over = collapse(c.over))

collapse(c::JoinClause) =
    JoinClause(over = collapse(c.over),
               joinee = collapse(c.joinee),
               on = collapse(c.on),
               left = c.left, right = c.right, lateral = c.lateral)

function collapse(c::SelectClause)
    over′ = collapse(c.over)
    list′ = collapse(c.list)
    d = decompose(over′)
    list′ = substitute(list′, d.subs)
    SelectClause(over = d.tail, distinct = c.distinct, list = unalias(list′))
end

collapse(c::WhereClause) =
    WhereClause(over = collapse(c.over), condition = collapse(c.condition))

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
                        SELECT(distinct = false, list = select_list) |>
                        AS(name = alias))
        subs = substitutions(alias, select_list)
        subs !== nothing || return
        return Decomposition(tail, subs)
    end
end

function decompose(c::JoinClause)
    subs = Dict{Tuple{Symbol, Symbol}, SQLClause}()
    if @dissect c.joinee ((table := (nothing |> ID() |> AS())) |>
                          FROM() |>
                          SELECT(distinct = false, list = select_list) |>
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

function decompose(c::WhereClause)
    d = decompose(c.over)
    condition′ = substitute(c.condition, d.subs)
    if @dissect d.tail (tail := nothing || FROM() || JOIN())
        c′ = WHERE(over = tail, condition = condition′)
        return Decomposition(c′, d.subs)
    elseif @dissect d.tail (tail |> WHERE(condition = tail_condition))
        if @dissect tail_condition OP(name = :AND, args = args)
            condition′ = OP(:AND, args..., condition′)
        else
            condition′ = OP(:AND, tail_condition, condition′)
        end
        c′ = WHERE(over = tail, condition = condition′)
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
            push!(args, arg)
        else
            arg = :(c.$(f))
            push!(args, arg)
        end
    end
    if isempty(exs)
        return :(return c)
    end
    push!(exs, :($c($(args...))))
    Expr(:block, exs...)
end

