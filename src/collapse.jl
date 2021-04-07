# Collapsing SQL subqueries.

collapse(c::AbstractSQLClause) =
    c

collapse(c::SQLClause) =
    collapse(c[]) |> SQLClause

collapse(cs::Vector{SQLClause}) =
    SQLClause[collapse(c) for c in cs]

function substitutions(cs::Vector{SQLClause})
    subs = Dict{Symbol, SQLClause}()
    for c in cs
        if @dissect c AS(over = repl, name = name)
        elseif @dissect c ID(name = name)
            repl = c
        else
            continue
        end
        subs[name] = repl
    end
    subs
end

collapse(::Nothing) =
    nothing

collapse(c::AsClause) =
    AsClause(over = collapse(c.over), name = c.name)

collapse(c::FromClause) =
    FromClause(over = collapse(c.over))

function collapse(c::SelectClause)
    list = collapse(c.list)
    c = SelectClause(over = collapse(c.over), distinct = c.distinct, list = unalias(list))
    @dissect(c.over, select_over |>
                     SELECT(distinct = false, list = select_list) |>
                     AS(name = alias) |>
                     FROM()) || return c
    subs = substitutions(select_list)
    subs !== nothing || return c
    list′ = substitute(list, alias, subs)
    SelectClause(over = select_over, distinct = c.distinct, list = unalias(list′))
end

function collapse(c::WhereClause)
    c = WhereClause(over = collapse(c.over), condition = collapse(c.condition))
    @dissect(c.over, (tail := nothing || FROM() || WHERE()) |>
                     SELECT(distinct = false, list = select_list) |>
                     AS(name = alias) |>
                     FROM()) || return c
    subs = substitutions(select_list)
    subs !== nothing || return c
    condition′ = substitute(c.condition, alias, subs)
    if @dissect tail (tail |> WHERE(condition = tail_condition))
        if @dissect tail_condition OP(name = :AND, args = args)
            condition′ = OP(:AND, args..., condition′)
        else
            condition′ = OP(:AND, tail_condition, condition′)
        end
    end
    c′ = WHERE(over = tail, condition = condition′)
    c′ = SELECT(over = c′, list = select_list)
    c′ = AS(over = c′, name = alias)
    FromClause(over = c′)
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

function substitute(c::SQLClause, alias::Symbol, subs::Dict{Symbol, SQLClause})
    if @dissect c nothing |> ID(name = base_name) |> ID(name = name)
        if base_name === alias && name in keys(subs)
            return subs[name]
        end
    end
    substitute(c[], alias, subs)
end

substitute(cs::Vector{SQLClause}, alias::Symbol, subs::Dict{Symbol, SQLClause}) =
    SQLClause[substitute(c, alias, subs) for c in cs]

substitute(::Nothing, alias::Symbol, subs::Dict{Symbol, SQLClause}) =
    nothing

@generated function substitute(c::AbstractSQLClause, alias::Symbol, subs::Dict{Symbol, SQLClause})
    exs = Expr[]
    args = Expr[]
    fs = fieldnames(c)
    for f in fs
        t = fieldtype(c, f)
        if t === SQLClause || t === Union{SQLClause, Nothing} || t === Vector{SQLClause}
            ex = quote
                $(f) = substitute(c.$(f), alias, subs)
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

