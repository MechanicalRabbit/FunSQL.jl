# From node.

mutable struct FromNode <: AbstractSQLNode
    table::SQLTable

    FromNode(; table) =
        new(table)
end

FromNode(table) =
    FromNode(table = table)

From(args...; kws...) =
    FromNode(args...; kws...) |> SQLNode

Base.convert(::Type{AbstractSQLNode}, table::SQLTable) =
    FromNode(table)

function PrettyPrinting.quoteof(n::FromNode; limit::Bool = false, wrap::Bool = false)
    Expr(:call,
         wrap ? nameof(From) : nameof(FromNode),
         !limit ? quoteof(n.table, limit=true) : :…)
end

alias(n::FromNode) =
    n.table.name

star(n::FromNode) =
    SQLNode[Get(over = n, name = col) for col in n.table.columns]

function resolve(n::FromNode, req)
    output_columns = Set{Symbol}()
    for ref in req.refs
        core = ref[]
        if core isa GetNode && (core.over === nothing || core.over[] === n)
            if core.name in n.table.column_set && !(core.name in output_columns)
                push!(output_columns, core.name)
            end
        end
    end
    list = SQLClause[ID(col)
                     for col in n.table.columns
                     if col in output_columns]
    if isempty(list)
        push!(list, true)
    end
    c = SELECT(over = FROM(n.table.name), list = list)
    repl = Dict{SQLNode, Symbol}()
    for ref in req.refs
        core = ref[]
        if core isa GetNode && (core.over === nothing || core.over[] === n)
            if core.name in output_columns
                repl[ref] = core.name
            end
        end
    end
    ResolveResult(c, repl)
end

