# Rendering SQL.

"""
    render(query; tables = Dict{Symbol, SQLTable}(),
                  dialect = :default,
                  cache = nothing)::SQLString

Create a [`SQLCatalog`](@ref) object and serialize the query node.
"""
render(q; tables = Dict{Symbol, SQLTable}(), dialect = :default, cache = nothing) =
    render(SQLCatalog(tables = tables, dialect = dialect, cache = cache), q)

render(catalog::Union{SQLConnection, SQLCatalog}, q) =
    render(catalog, convert(SQLQuery, q))

"""
    render(catalog::Union{SQLConnection, SQLCatalog}, query::SQLQuery)::SQLString

Serialize the query node as a SQL statement.

Parameter `catalog` of [`SQLCatalog`](@ref) type encapsulates available
database tables and the target SQL dialect.  A [`SQLConnection`](@ref) object
is also accepted.

Parameter `query` is a [`SQLQuery`](@ref) object.

The function returns a [`SQLString`](@ref) value.  The result is also cached
(with the identity of `query` serving as the key) in the catalog cache.

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
function render(catalog::SQLCatalog, q::SQLQuery)
    cache = catalog.cache
    if cache !== nothing
        sql = get(cache, q, nothing)
        if sql !== nothing
            return sql
        end
    end
    q′ = resolve(WithContext(catalog = catalog, tail = q))
    @debug "FunSQL.resolve\n" * sprint(pprint, q′) _group = Symbol("FunSQL.resolve")
    q′′ = link(q′)
    @debug "FunSQL.link\n" * sprint(pprint, q′′) _group = Symbol("FunSQL.link")
    s = translate(q′′)
    @debug "FunSQL.translate\n" * sprint(pprint, s) _group = Symbol("FunSQL.translate")
    sql = serialize(s)
    @debug "FunSQL.serialize\n" * sprint(pprint, sql) _group = Symbol("FunSQL.serialize")
    if cache !== nothing
        cache[q] = sql
    end
    sql
end

render(conn::SQLConnection, q::SQLQuery) =
    render(conn.catalog, q)

"""
    render(dialect::Union{SQLConnection, SQLCatalog, SQLDialect},
           syntax::SQLSyntax)::SQLString

Serialize the syntax tree of a SQL query.
"""
function render(dialect::SQLDialect, s::SQLSyntax)
    serialize(WITH_CONTEXT(dialect = dialect, tail = s))
end

render(conn::SQLConnection, s::SQLSyntax) =
    render(conn.catalog, s)

render(catalog::SQLCatalog, s::SQLSyntax) =
    render(catalog.dialect, s)

render(dialect::Union{SQLConnection, SQLCatalog, SQLDialect}, s) =
    render(dialect, convert(SQLSyntax, s))
