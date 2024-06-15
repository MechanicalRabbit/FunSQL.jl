# Database structure.

const SQLMetadata = Base.ImmutableDict{Symbol, Any}

_metadata(::Nothing) =
    SQLMetadata()

_metadata(dict::SQLMetadata) =
    dict

_metadata(dict::SQLMetadata, kvs...) =
    Base.ImmutableDict(dict, kvs...)

_metadata(other) =
    _metadata(SQLMetadata(), pairs(other)...)

"""
    SQLColumn(; name, metadata = nothing)
    SQLColumn(name; metadata = nothing)

`SQLColumn` represents a column with the given `name` and optional `metadata`.
"""
struct SQLColumn
    name::Symbol
    metadata::SQLMetadata

    function SQLColumn(; name::Union{Symbol, AbstractString}, metadata = nothing)
        new(Symbol(name), _metadata(metadata))
    end
end

SQLColumn(name; metadata = nothing) =
    SQLColumn(name = name, metadata = metadata)

Base.show(io::IO, col::SQLColumn) =
    print(io, quoteof(col, limit = true))

Base.show(io::IO, ::MIME"text/plain", col::SQLColumn) =
    pprint(io, col)

function PrettyPrinting.quoteof(col::SQLColumn; limit::Bool = false)
    ex = Expr(:call, nameof(SQLColumn), QuoteNode(col.name))
    if !isempty(col.metadata)
        push!(ex.args, Expr(:kw, :metadata, limit ? :… : quoteof(reverse!(collect(col.metadata)))))
    end
    ex
end

_column_map(columns::OrderedDict{Symbol, SQLColumn}) =
    columns

_column_map(columns::AbstractVector{Pair{Symbol, SQLColumn}}) =
    OrderedDict{Symbol, SQLColumn}(columns)

_column_map(columns) =
    OrderedDict{Symbol, SQLColumn}(Pair{Symbol, SQLColumn}[_column_entry(c) for c in columns])

_column_entry(c::Symbol) =
    c => SQLColumn(c)

_column_entry(c::AbstractString) =
    _column_entry(Symbol(c))

_column_entry(c::SQLColumn) =
    c.name => c

_column_entry((n, c)::Pair{<:Union{Symbol, AbstractString}, SQLColumn}) =
    Symbol(n) => c

"""
    SQLTable(; qualifiers = [], name, columns, metadata = nothing)
    SQLTable(name; qualifiers = [], columns, metadata = nothing)
    SQLTable(name, columns...; qualifiers = [], metadata = nothing)

The structure of a SQL table or a table-like entity (`TEMP TABLE`, `VIEW`, etc)
for use as a reference in assembling SQL queries.

The `SQLTable` constructor expects the table `name`, an optional vector
containing the table schema and other `qualifiers`, an ordered dictionary
`columns` that maps names to columns, and an optional `metadata`.

# Examples

```jldoctest
julia> person = SQLTable(qualifiers = ["public"],
                         name = "person",
                         columns = ["person_id", "year_of_birth"],
                         metadata = (; is_view = false))
SQLTable(qualifiers = [:public],
         :person,
         SQLColumn(:person_id),
         SQLColumn(:year_of_birth),
         metadata = [:is_view => false])
```
"""
struct SQLTable <: AbstractDict{Symbol, SQLColumn}
    qualifiers::Vector{Symbol}
    name::Symbol
    columns::OrderedDict{Symbol, SQLColumn}
    metadata::SQLMetadata

    function SQLTable(;
                      qualifiers::AbstractVector{<:Union{Symbol, AbstractString}} = Symbol[],
                      name::Union{Symbol, AbstractString},
                      columns,
                      metadata = nothing)
        qualifiers =
            !isa(qualifiers, Vector{Symbol}) ?
                Symbol[Symbol(ql) for ql in qualifiers] :
                qualifiers
        name = Symbol(name)
        columns = _column_map(columns)
        new(qualifiers, name, columns, _metadata(metadata))
    end
end

SQLTable(name; qualifiers = Symbol[], columns, metadata = nothing) =
    SQLTable(qualifiers = qualifiers, name = name, columns = columns, metadata = metadata)

SQLTable(name, columns...; qualifiers = Symbol[], metadata = nothing) =
    SQLTable(qualifiers = qualifiers, name = name, columns = [columns...], metadata = metadata)

Base.show(io::IO, tbl::SQLTable) =
    print(io, quoteof(tbl, limit = true))

Base.show(io::IO, ::MIME"text/plain", tbl::SQLTable) =
    pprint(io, tbl)

function PrettyPrinting.quoteof(tbl::SQLTable; limit::Bool = false)
    ex = Expr(:call, nameof(SQLTable))
    if !isempty(tbl.qualifiers)
        push!(ex.args, Expr(:kw, :qualifiers, quoteof(tbl.qualifiers)))
    end
    push!(ex.args, quoteof(tbl.name))
    if !limit
        for (name, col) in tbl.columns
            arg = quoteof(col)
            if name !== col.name
                arg = Expr(:call, :(=>), QuoteNode(name), arg)
            end
            push!(ex.args, arg)
        end
        if !isempty(tbl.metadata)
            push!(ex.args, Expr(:kw, :metadata, quoteof(reverse!(collect(tbl.metadata)))))
        end
    else
        push!(ex.args, :…)
    end
    ex
end

Base.get(tbl::SQLTable, key::Union{Symbol, AbstractString}, default) =
    get(tbl.columns, Symbol(key), default)

Base.get(default::Base.Callable, tbl::SQLTable, key::Union{Symbol, AbstractString}) =
    get(default, tbl.columns, Symbol(key))

Base.getindex(tbl::SQLTable, key::Union{Symbol, AbstractString}) =
    tbl.columns[Symbol(key)]

Base.iterate(tbl::SQLTable, state...) =
    iterate(tbl.columns, state...)

Base.length(tbl::SQLTable) =
    length(tbl.columns)

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
                 cache = $default_cache_maxsize,
                 metadata = nothing)
    SQLCatalog(tables...;
               dialect = :default, cache = $default_cache_maxsize, metadata = nothing)

`SQLCatalog` encapsulates available database `tables`, the target SQL `dialect`,
a `cache` of serialized queries, and an optional `metadata`.

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
SQLCatalog(SQLTable(:location, SQLColumn(:location_id), SQLColumn(:state)),
           SQLTable(:person,
                    SQLColumn(:person_id),
                    SQLColumn(:year_of_birth),
                    SQLColumn(:location_id)),
           dialect = SQLDialect(:postgresql))
```
"""
struct SQLCatalog <: AbstractDict{Symbol, SQLTable}
    tables::Dict{Symbol, SQLTable}
    dialect::SQLDialect
    cache::Any # Union{AbstractDict{SQLNode, SQLString}, Nothing}
    metadata::SQLMetadata

    function SQLCatalog(; tables = Dict{Symbol, SQLTable}(), dialect = :default, cache = default_cache_maxsize, metadata = nothing)
        table_map = _table_map(tables)
        if cache isa Number
            cache = LRU{SQLNode, SQLString}(maxsize = cache)
        end
        new(table_map, dialect, cache, _metadata(metadata))
    end
end

SQLCatalog(tables...; dialect = :default, cache = default_cache_maxsize, metadata = nothing) =
    SQLCatalog(tables = tables, dialect = dialect, cache = cache, metadata = metadata)

function PrettyPrinting.quoteof(c::SQLCatalog)
    ex = Expr(:call, nameof(SQLCatalog))
    for name in sort!(collect(keys(c.tables)))
        tbl = c.tables[name]
        arg = quoteof(tbl)
        if name !== tbl.name
            arg = Expr(:call, :(=>), QuoteNode(name), arg)
        end
        push!(ex.args, arg)
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
    if !isempty(c.metadata)
        push!(ex.args, Expr(:kw, :metadata, quoteof(reverse!(collect(c.metadata)))))
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
    if !isempty(c.metadata)
        print(io, ", metadata = …")
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

