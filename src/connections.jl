# DBInterface bridge.

"""
    SQLConnection(conn; catalog)

Wrap a raw database connection object together with a [`SQLCatalog`](@ref)
object containing information about database tables.
"""
struct SQLConnection{RawConnType} <: DBInterface.Connection
    raw::RawConnType
    catalog::SQLCatalog

    SQLConnection{RawConnType}(raw::RawConnType; catalog) where {RawConnType} =
        new{RawConnType}(raw, catalog)
end

SQLConnection(raw::RawConnType; catalog) where {RawConnType} =
    SQLConnection{RawConnType}(raw, catalog = catalog)

"""
    SQLStatement(conn, raw; vars = Symbol[])

Wrap a prepared SQL statement.
"""
struct SQLStatement{RawConnType, RawStmtType} <: DBInterface.Statement
    conn::SQLConnection{RawConnType}
    raw::RawStmtType
    vars::Vector{Symbol}

    SQLStatement{RawConnType, RawStmtType}(conn::SQLConnection{RawConnType}, raw::RawStmtType; vars = Symbol[]) where {RawConnType, RawStmtType} =
        new(conn, raw, vars)
end

SQLStatement(conn::SQLConnection{RawConnType}, raw::RawStmtType; vars = Symbol[]) where {RawConnType, RawStmtType} =
    SQLStatement{RawConnType, RawStmtType}(conn, raw, vars = vars)

"""
Shorthand for [`SQLConnection`](@ref).
"""
const DB = SQLConnection

"""
    DBInterface.connect(DB{RawConnType},
                        args...;
                        catalog = nothing,
                        schema = nothing,
                        dialect = nothing,
                        cache = $default_cache_maxsize,
                        kws...)

Connect to the database server and return a [`SQLConnection`](@ref) object.

The function creates a raw database connection object by calling:

    DBInterface.connect(RawConnType, args...; kws...)

If `catalog` is not set, it is retrieved from the database
using [`reflect`](@ref), which consumes the parameters `schema`,
`dialect`, and `cache`.
"""
function DBInterface.connect(::Type{SQLConnection{RawConnType}}, args...;
                             catalog::Union{SQLCatalog, Nothing} = nothing,
                             schema = nothing,
                             dialect = nothing,
                             cache = default_cache_maxsize,
                             kws...) where {RawConnType}
    raw = DBInterface.connect(RawConnType, args...; kws...)
    if catalog === nothing
        catalog = reflect(raw, schema = schema, dialect = dialect, cache = cache)
    end
    SQLConnection{RawConnType}(raw, catalog = catalog)
end

"""
    DBInterface.prepare(conn::SQLConnection, sql::SQLNode)::SQLStatement
    DBInterface.prepare(conn::SQLConnection, sql::SQLClause)::SQLStatement

Serialize the query node and return a prepared SQL statement.
"""
DBInterface.prepare(conn::SQLConnection, sql::Union{AbstractSQLNode, AbstractSQLClause}) =
    DBInterface.prepare(conn, render(conn, sql))

"""
    DBInterface.prepare(conn::SQLConnection, str::SQLString)::SQLStatement

Generate a prepared SQL statement.
"""
DBInterface.prepare(conn::SQLConnection, str::SQLString) =
    SQLStatement(conn, DBInterface.prepare(conn.raw, str.raw), vars = str.vars)

DBInterface.prepare(conn::SQLConnection, str::AbstractString) =
    DBInterface.prepare(conn.raw, str)

"""
    DBInterface.execute(conn::SQLConnection, sql::SQLNode; params...)
    DBInterface.execute(conn::SQLConnection, sql::SQLClause; params...)

Serialize and execute the query node.
"""
DBInterface.execute(conn::SQLConnection, sql::Union{AbstractSQLNode, AbstractSQLClause}; params...) =
    DBInterface.execute(conn, sql, values(params))

"""
    DBInterface.execute(conn::SQLConnection, sql::SQLNode, params)
    DBInterface.execute(conn::SQLConnection, sql::SQLClause, params)

Serialize and execute the query node.
"""
DBInterface.execute(conn::SQLConnection, sql::Union{AbstractSQLNode, AbstractSQLClause}, params) =
    DBInterface.execute(DBInterface.prepare(conn, sql), params)

DBInterface.close!(conn::SQLConnection) =
    DBInterface.close!(conn.raw)

"""
    DBInterface.execute(stmt::SQLStatement, params)

Execute the prepared SQL statement.
"""
DBInterface.execute(stmt::SQLStatement, params) =
    DBInterface.execute(stmt.raw, pack(stmt.vars, params))

DBInterface.getconnection(stmt::SQLStatement) =
    stmt.conn

DBInterface.close!(stmt::SQLStatement) =
    DBInterface.close(stmt.raw)

