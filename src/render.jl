# Rendering SQL.

"""
    render(node; tables = Dict{Symbol, SQLTable}(),
                 dialect = :default,
                 cache = nothing)::SQLString

Create a [`SQLCatalog`](@ref) object and serialize the query node.
"""
render(n; tables = Dict{Symbol, SQLTable}(), dialect = :default, cache = nothing) =
    render(SQLCatalog(tables = tables, dialect = dialect, cache = cache), n)

render(catalog::Union{SQLConnection, SQLCatalog}, n) =
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
    n = WithContext(over = n, catalog = catalog)
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

render(conn::SQLConnection, n::SQLNode) =
    render(conn.catalog, n)

"""
    render(dialect::Union{SQLConnection, SQLCatalog, SQLDialect},
           syntax::SQLSyntax)::SQLString

Serialize the syntax tree of a SQL query.
"""
function render(dialect::SQLDialect, s::SQLSyntax)
    s = WITH_CONTEXT(tail = s, dialect = dialect)
    sql = serialize(s)
    sql
end

render(conn::SQLConnection, s::SQLSyntax) =
    render(conn.catalog, s)

render(catalog::SQLCatalog, s::SQLSyntax) =
    render(catalog.dialect, s)

render(dialect::Union{SQLConnection, SQLCatalog, SQLDialect}, s) =
    render(dialect, convert(SQLSyntax, s))
