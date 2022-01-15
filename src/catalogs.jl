# Database structure.

"""
    SQLTable(; schema = nothing, name, columns)
    SQLTable(name; schema = nothing, columns)
    SQLTable(name, columns...; schema = nothing)

The structure of a SQL table or a table-like entity (`TEMP TABLE`, `VIEW`, etc)
for use as a reference in assembling SQL queries.

The `SQLTable` constructor expects the table `name`, a vector `columns` of
column names, and, optionally, the name of the table `schema`.  A name can be
a `Symbol` or a `String` value.

# Examples

```jldoctest
julia> person = SQLTable(schema = "public",
                         name = "person",
                         columns = ["person_id", "year_of_birth"])
SQLTable(:person, schema = :public, columns = [:person_id, :year_of_birth])
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

const default_cache_maxsize = 256

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

"""
    SQLCatalog(; tables = Dict{Symbol, SQLTable}(),
                 dialect = :default,
                 cache = $default_cache_maxsize)
    SQLCatalog(tables...; dialect = :default, cache = $default_cache_maxsize)

`SQLCatalog` encapsulates available database `tables`, the target SQL `dialect`,
and a `cache` of serialized queries.

Parameter `tables` is either a dictionary or a vector of [`SQLTable`](@ref)
objects, where the vector will be converted to a dictionary with
table names as keys.  A table in the catalog can be included to
a query using the [`From`](@ref) node.

Parameter `dialect` is a [`SQLDialect`](@ref) object describing the target
SQL dialect.

Parameter `cache` specifies the size of the LRU cache containing results
of the [`render`](@ref) function.  Set `cache` to `nothing` to disable
the cache, or set `cache` to an arbitrary `Dict`-like object to provide
a custom cache implementation.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id]);

julia> location = SQLTable(:location, columns = [:location_id, :state]);

julia> catalog = SQLCatalog(person, location, dialect = :postgresql)
SQLCatalog(:location => SQLTable(:location, columns = [:location_id, :state]),
           :person =>
               SQLTable(:person,
                        columns = [:person_id, :year_of_birth, :location_id]),
           dialect = SQLDialect(:postgresql))
```
"""
struct SQLCatalog <: AbstractDict{Symbol, SQLTable}
    tables::Dict{Symbol, SQLTable}
    dialect::SQLDialect
    cache::Any # Union{AbstractDict{SQLNode, SQLString}, Nothing}

    function SQLCatalog(; tables = Dict{Symbol, SQLTable}(), dialect = :default, cache = default_cache_maxsize)
        table_map = _table_map(tables)
        if cache isa Number
            cache = LRU{SQLNode, SQLString}(maxsize = cache)
        end
        new(table_map, dialect, cache)
    end
end

SQLCatalog(tables...; dialect = :default, cache = default_cache_maxsize) =
    SQLCatalog(tables = tables, dialect = dialect, cache = cache)

function PrettyPrinting.quoteof(c::SQLCatalog)
    ex = Expr(:call, nameof(SQLCatalog))
    for name in sort!(collect(keys(c.tables)))
        push!(ex.args, Expr(:call, :(=>), QuoteNode(name), quoteof(c.tables[name])))
    end
    push!(ex.args, Expr(:kw, :dialect, quoteof(c.dialect)))
    cache = c.cache
    if cache === nothing
        push!(ex.args, Expr(:kw, :cache, nothing))
    elseif cache isa LRU{SQLNode, SQLString}
        if cache.maxsize != default_cache_maxsize
            push!(ex.args, Expr(:kw, :cache, cache.maxsize))
        end
    else
        push!(ex.args, Expr(:kw, :cache, Expr(:call, typeof(cache))))
    end
    ex
end

function Base.show(io::IO, c::SQLCatalog)
    print(io, "SQLCatalog(")
    l = length(c.tables)
    if l == 1
        print(io, "…1 table…, ")
    elseif l > 1
        print(io, "…$l tables…, ")
    end
    print(io, "dialect = ", c.dialect)
    cache = c.cache
    if cache === nothing
        print(io, ", cache = nothing")
    elseif cache isa LRU{SQLNode, SQLString}
        if cache.maxsize != default_cache_maxsize
            print(io, ", cache = ", cache.maxsize)
        end
    else
        print(io, ", cache = ", typeof(cache), "()")
    end
    print(io, ')')
    nothing
end

Base.show(io::IO, ::MIME"text/plain", c::SQLCatalog) =
    pprint(io, c)

Base.get(c::SQLCatalog, key::Union{Symbol, AbstractString}, default) =
    get(c.tables, Symbol(key), default)

Base.get(default::Base.Callable, c::SQLCatalog, key::Union{Symbol, AbstractString}) =
    get(default, c.tables, Symbol(key))

Base.getindex(c::SQLCatalog, key::Union{Symbol, AbstractString}) =
    c.tables[Symbol(key)]

Base.iterate(c::SQLCatalog, state...) =
    iterate(c.tables, state...)

Base.length(c::SQLCatalog) =
    length(c.tables)

