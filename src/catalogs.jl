# Database structure.

"""
    SQLTable(; schema = nothing, name, columns)
    SQLTable(name; schema = nothing, columns)
    SQLTable(name, columns...; schema = nothing)

The structure of a SQL table or a table-like entity (TEMP TABLE, VIEW, etc) for
use as a reference in assembling SQL queries.

The `SQLTable` constructor expects the table `name`, a vector `columns` of
column names, and, optionally, the name of the table `schema`.  A name can be
provided as a `Symbol` or `String` value.

# Examples

```jldoctest
julia> t = SQLTable(:location,
                    :location_id, :address_1, :address_2, :city, :state, :zip);


julia> show(t.name)
:location

julia> show(t.columns)
[:location_id, :address_1, :address_2, :city, :state, :zip]
```

```jldoctest
julia> t = SQLTable(schema = "public",
                    name = "person",
                    columns = ["person_id", "birth_datetime", "location_id"]);

julia> show(t.schema)
:public

julia> show(t.name)
:person

julia> show(t.columns)
[:person_id, :birth_datetime, :location_id]
```
"""
struct SQLTable
    schema::Union{Symbol, Nothing}
    name::Symbol
    columns::Vector{Symbol}
    column_set::Set{Symbol}

    function SQLTable(;
                      schema::Union{Symbol, AbstractString, Nothing} = nothing,
                      name::Union{Symbol, AbstractString},
                      columns::AbstractVector{<:Union{Symbol, AbstractString}})
        schema = schema !== nothing ? Symbol(schema) : nothing
        name = Symbol(name)
        columns =
            !isa(columns, Vector{Symbol}) ?
                Symbol[Symbol(col) for col in columns] :
                columns
        column_set = Set{Symbol}(columns)
        new(schema, name, columns, column_set)
    end
end

SQLTable(name; schema = nothing, columns) =
    SQLTable(schema = schema, name = name, columns = columns)

SQLTable(name, columns...; schema = nothing) =
    SQLTable(schema = schema, name = name, columns = [columns...])

Base.show(io::IO, tbl::SQLTable) =
    print(io, quoteof(tbl, limit = true))

Base.show(io::IO, ::MIME"text/plain", tbl::SQLTable) =
    pprint(io, tbl)

function PrettyPrinting.quoteof(tbl::SQLTable; limit::Bool = false)
    ex = Expr(:call, nameof(SQLTable))
    push!(ex.args, quoteof(tbl.name))
    if tbl.schema !== nothing
        push!(ex.args, Expr(:kw, :schema, quoteof(tbl.schema)))
    end
    if !limit
        push!(ex.args, Expr(:kw, :columns, tbl.columns))
    else
        push!(ex.args, :…)
    end
    ex
end

const default_cache_maxsize = 1024

_table_map(tables::Dict{Symbol, SQLTable}) =
    tables

_table_map(tables::AbstractVector{Pair{Symbol, SQLTable}}) =
    Dict{Symbol, SQLTable}(tables)

_table_map(tables) =
    Dict{Symbol, SQLTable}(Pair{Symbol, SQLTable}[_table_entry(t) for t in tables])

_table_entry(t::SQLTable) =
    t.name => t

_table_entry((n, t)::Pair{<:Union{Symbol, AbstractString}, SQLTable}) =
    Symbol(n) => t

struct SQLCatalog <: AbstractDict{Symbol, SQLTable}
    table_map::Dict{Symbol, SQLTable}
    dialect::SQLDialect
    cache::Union{LRU{Any, SQLString}, Nothing}

    function SQLCatalog(; tables = Dict{Symbol, SQLTable}(), dialect = :default, cache_maxsize = 1024)
        table_map = _table_map(tables)
        cache =
            cache_maxsize > 0 ?
            LRU{Any, SQLString}(maxsize = cache_maxsize) :
            nothing
        new(table_map, dialect, cache)
    end
end

SQLCatalog(tables...; dialect = :default, cache_maxsize = default_cache_maxsize) =
    SQLCatalog(tables = tables, dialect = dialect, cache_maxsize = cache_maxsize)

function PrettyPrinting.quoteof(c::SQLCatalog)
    ex = Expr(:call, nameof(SQLCatalog))
    for name in sort!(collect(keys(c.table_map)))
        push!(ex.args, Expr(:call, :(=>), QuoteNode(name), quoteof(c.table_map[name])))
    end
    push!(ex.args, Expr(:kw, :dialect, quoteof(c.dialect)))
    cache = c.cache
    if cache === nothing
        push!(ex.args, Expr(:kw, :cache_maxsize, 0))
    elseif cache.maxsize != default_cache_maxsize
        push!(ex.args, Expr(:kw, :cache_maxsize, cache.maxsize))
    end
    ex
end

function Base.show(io::IO, c::SQLCatalog)
    print(io, "SQLCatalog(")
    l = length(c.table_map)
    if l == 1
        print(io, "…1 table…, ")
    elseif l > 1
        print(io, "…$l tables…, ")
    end
    print(io, "dialect = ", c.dialect)
    cache = c.cache
    if cache === nothing
        print(io, ", cache_maxsize = 0")
    elseif cache.maxsize != default_cache_maxsize
        print(io, ", cache_maxsize = ", cache.maxsize)
    end
    print(io, ')')
    nothing
end

Base.show(io::IO, ::MIME"text/plain", c::SQLCatalog) =
    pprint(io, c)

Base.get(c::SQLCatalog, key::Union{Symbol, AbstractString}, default) =
    get(c.table_map, Symbol(key), default)

Base.get(default::Base.Callable, c::SQLCatalog, key::Union{Symbol, AbstractString}) =
    get(default, c.table_map, Symbol(key))

Base.getindex(c::SQLCatalog, key::Union{Symbol, AbstractString}) =
    c.table_map[Symbol(key)]

Base.iterate(c::SQLCatalog, state...) =
    iterate(c.table_map, state...)

Base.length(c::SQLCatalog) =
    length(c.table_map)

