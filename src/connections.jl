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

function Base.show(io::IO, conn::SQLConnection)
    print(io, "SQLConnection(")
    show(io, conn.raw)
    print(io, ", catalog = ")
    show(io, conn.catalog)
    print(io, ')')
end

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

function Base.show(io::IO, stmt::SQLStatement)
    print(io, "SQLStatement(")
    show(io, stmt.conn)
    print(io, ", ")
    show(io, stmt.raw)
    if !isempty(stmt.vars)
        print(io, ", vars = ")
        show(io, stmt.vars)
    end
    print(io, ')')
end

"""
Shorthand for [`SQLConnection`](@ref).
"""
const DB = SQLConnection

"""
    SQLCursor(raw)

Wraps the query result.
"""
struct SQLCursor{RawCrType} <: DBInterface.Cursor
    raw::RawCrType

    SQLCursor{RawCrType}(raw::RawCrType) where {RawCrType} =
        new(raw)
end

SQLCursor(raw::RawCrType) where {RawCrType} =
    SQLCursor{RawCrType}(raw)

function Base.show(io::IO, cr::SQLCursor)
    print(io, "SQLCursor(")
    show(io, cr.raw)
    print(io, ")")
end

Base.eltype(cr::SQLCursor) =
   eltype(cr.raw)

Base.IteratorSize(::Type{SQLCursor{RawCrType}}) where {RawCrType} =
    Base.IteratorSize(RawCrType)

Base.length(cr::SQLCursor) =
    length(cr.raw)

Base.iterate(cr::SQLCursor, state...) =
    iterate(cr.raw, state...)

Tables.istable(::Type{SQLCursor{RawCrType}}) where {RawCrType} =
    Tables.istable(RawCrType)

Tables.rowaccess(::Type{SQLCursor{RawCrType}}) where {RawCrType} =
    Tables.rowaccess(RawCrType)

Tables.rows(cr::SQLCursor) =
    Tables.rows(cr.raw)

Tables.columnaccess(::Type{SQLCursor{RawCrType}}) where {RawCrType} =
    Tables.columnaccess(RawCrType)

Tables.columns(cr::SQLCursor) =
    Tables.columns(cr.raw)

Tables.schema(cr::SQLCursor) =
    Tables.schema(cr.raw)

"""
    DBInterface.connect(DB{RawConnType},
                        args...;
                        catalog = nothing,
                        schema = nothing,
                        dialect = nothing,
                        cache = $default_cache_maxsize,
                        kws...)

Connect to the database server, call [`reflect`](@ref) to retrieve the
information about available tables and return a [`SQLConnection`](@ref) object.

Extra parameters `args` and `kws` are passed to the call:

    DBInterface.connect(RawConnType, args...; kws...)
"""
function DBInterface.connect(::Type{SQLConnection{RawConnType}}, args...;
                             catalog = nothing,
                             schema = nothing,
                             dialect = nothing,
                             cache = default_cache_maxsize,
                             kws...) where {RawConnType}
    raw = DBInterface.connect(RawConnType, args...; kws...)
    SQLConnection{RawConnType}(raw; catalog = reflect(raw; catalog, schema, dialect, cache))
end

"""
    DBInterface.prepare(conn::SQLConnection, sql::SQLQuery)::SQLStatement
    DBInterface.prepare(conn::SQLConnection, sql::SQLSyntax)::SQLStatement

Serialize the query node and return a prepared SQL statement.
"""
DBInterface.prepare(conn::SQLConnection, sql::Union{SQLQuery, SQLSyntax}) =
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
    DBInterface.execute(conn::SQLConnection, sql::SQLQuery; params...)
    DBInterface.execute(conn::SQLConnection, sql::SQLSyntax; params...)

Serialize and execute the query node.
"""
DBInterface.execute(conn::SQLConnection, sql::Union{SQLQuery, SQLSyntax}; params...) =
    DBInterface.execute(conn, sql, values(params))

"""
    DBInterface.execute(conn::SQLConnection, sql::SQLQuery, params)
    DBInterface.execute(conn::SQLConnection, sql::SQLSyntax, params)

Serialize and execute the query node.
"""
DBInterface.execute(conn::SQLConnection, sql::Union{SQLQuery, SQLSyntax}, params) =
    DBInterface.execute(DBInterface.prepare(conn, sql), params)

DBInterface.close!(conn::SQLConnection) =
    DBInterface.close!(conn.raw)

"""
    DBInterface.execute(stmt::SQLStatement, params)

Execute the prepared SQL statement.
"""
DBInterface.execute(stmt::SQLStatement, params) =
    SQLCursor(DBInterface.execute(stmt.raw, pack(stmt.vars, params)))

DBInterface.getconnection(stmt::SQLStatement) =
    stmt.conn

DBInterface.close!(stmt::SQLStatement) =
    DBInterface.close!(stmt.raw)

DBInterface.lastrowid(cr::SQLCursor) =
    DBInterface.lastrowid(cr.raw)

DBInterface.close!(cr::SQLCursor) =
    DBInterface.close!(cr.raw)
