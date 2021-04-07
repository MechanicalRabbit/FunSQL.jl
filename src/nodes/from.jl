# From node.

mutable struct FromNode <: SubqueryNode
    table::SQLTable

    FromNode(; table) =
        new(table)
end

FromNode(table) =
    FromNode(table = table)

"""
    From(; table)
    From(table)

A subquery that selects columns from the given table.

```sql
SELECT ... FROM \$table
```

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> print(render(q))
SELECT "person_1"."person_id", "person_1"."year_of_birth"
FROM "person" AS "person_1"
```
"""
From(args...; kws...) =
    FromNode(args...; kws...) |> SQLNode

Base.convert(::Type{AbstractSQLNode}, table::SQLTable) =
    FromNode(table)

function PrettyPrinting.quoteof(n::FromNode, qctx::SQLNodeQuoteContext)
    tex = get(qctx.vars, n.table, nothing)
    if tex === nothing
        tex = quoteof(n.table, limit = true)
    end
    Expr(:call, nameof(From), tex)
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
    as = allocate_alias(req.ctx, n.table.name)
    list = SQLClause[AS(over = ID(over = as, name = col), name = col)
                     for col in n.table.columns
                     if col in output_columns]
    if isempty(list)
        push!(list, true)
    end
    tbl = ID(over = n.table.schema, name = n.table.name)
    c = SELECT(over = FROM(AS(over = tbl, name = as)),
               list = list)
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

