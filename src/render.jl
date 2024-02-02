# Rendering SQL.

"""
    render(node; tables = Dict{Symbol, SQLTable}(),
                 dialect = :default,
                 cache = nothing)::SQLString

Create a [`SQLCatalog`](@ref) object and serialize the query node.
"""
render(n; tables = Dict{Symbol, SQLTable}(), dialect = :default, cache = nothing) =
    render(SQLCatalog(tables = tables, dialect = dialect, cache = cache), n)

render(conn::SQLConnection, n) =
    render(conn.catalog, n)

render(catalog::SQLCatalog, n) =
    render(catalog, convert(SQLNode, n))

"""
    render(catalog::Union{SQLConnection, SQLCatalog}, node::SQLNode)::SQLString

Serialize the query node as a SQL statement.

Parameter `catalog` of [`SQLCatalog`](@ref) type encapsulates available
database tables and the target SQL dialect.  A [`SQLConnection`](@ref) object
is also accepted.

Parameter `node` is a composite [`SQLNode`](@ref) object.

The function returns a [`SQLString`](@ref) value.  The result is also cached
(with the identity of `node` serving as the key) in the catalog cache.

# Examples

```jldoctest
julia> catalog = SQLCatalog(
           :person => SQLTable(:person, columns = [:person_id, :year_of_birth]),
           dialect = :postgresql);

julia> q = From(:person) |>
           Where(Get.year_of_birth .>= 1950);

julia> print(render(catalog, q))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."year_of_birth" >= 1950)
```
"""
function render(catalog::SQLCatalog, n::SQLNode)
    cache = catalog.cache
    if cache !== nothing
        sql = get(cache, n, nothing)
        if sql !== nothing
            return sql
        end
    end
    n = WithContext(over = n, dialect = catalog.dialect, tables = catalog.tables)
    n = resolve(n)
    @debug "FunSQL.resolve\n" * sprint(pprint, n) _group = Symbol("FunSQL.resolve")
    n = link(n)
    @debug "FunSQL.link\n" * sprint(pprint, n) _group = Symbol("FunSQL.link")
    c = translate(n)
    @debug "FunSQL.translate\n" * sprint(pprint, c) _group = Symbol("FunSQL.translate")
    sql = serialize(c)
    @debug "FunSQL.serialize\n" * sprint(pprint, sql) _group = Symbol("FunSQL.serialize")
    if cache !== nothing
        cache[n] = sql
    end
    sql
end

render(catalog::SQLCatalog, c::AbstractSQLClause) =
    render(catalog.dialect, c)

render(dialect::SQLDialect, c::AbstractSQLClause) =
    render(dialect, convert(SQLClause, c))

"""
    render(dialect::Union{SQLConnection, SQLCatalog, SQLDialect},
           clause::SQLClause)::SQLString

Serialize the syntax tree of a SQL query.
"""
function render(dialect::SQLDialect, c::SQLClause)
    c = WITH_CONTEXT(over = c, dialect = dialect)
    sql = serialize(c)
    sql
end

