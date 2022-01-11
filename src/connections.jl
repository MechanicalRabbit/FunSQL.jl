# DBInterface bridge.

struct SQLConnection{RawConnType} <: DBInterface.Connection
    raw::RawConnType
    catalog::SQLCatalog

    SQLConnection{RawConnType}(raw::RawConnType; catalog) where {RawConnType} =
        new{RawConnType}(raw, catalog)
end

SQLConnection(raw::RawConnType; catalog) where {RawConnType} =
    SQLConnection{RawConnType}(raw, catalog = catalog)

struct SQLStatement{RawConnType, RawStmtType} <: DBInterface.Statement
    conn::SQLConnection{RawConnType}
    raw::RawStmtType
    vars::Vector{Symbol}

    SQLStatement{RawConnType, RawStmtType}(conn::SQLConnection{RawConnType}, raw::RawStmtType; vars = Symbol[]) where {RawConnType, RawStmtType} =
        new(conn, raw, vars)
end

SQLStatement(conn::SQLConnection{RawConnType}, raw::RawStmtType; vars = Symbol[]) where {RawConnType, RawStmtType} =
    SQLStatement{RawConnType, RawStmtType}(conn, raw, vars = vars)

const DB = SQLConnection

function DBInterface.connect(::Type{SQLConnection{RawConnType}}, args...; catalog = nothing, dialect = nothing, kws...) where {RawConnType}
    raw = DBInterface.connect(RawConnType, args...; kws...)
    if catalog === nothing
        if dialect === nothing
            dialect = SQLDialect(RawConnType)
        end
        catalog = reflect(raw, dialect = dialect)
    end
    SQLConnection{RawConnType}(raw, catalog = catalog)
end

DBInterface.prepare(conn::SQLConnection, sql::Union{AbstractSQLNode, AbstractSQLClause}) =
    DBInterface.prepare(conn, render(conn, sql))

DBInterface.prepare(conn::SQLConnection, str::SQLString) =
    SQLStatement(conn, DBInterface.prepare(conn.raw, str.raw), vars = str.vars)

DBInterface.prepare(conn::SQLConnection, str::AbstractString) =
    DBInterface.prepare(conn.raw, str)

DBInterface.execute(conn::SQLConnection, sql::Union{AbstractSQLNode, AbstractSQLClause}; params...) =
    DBInterface.execute(conn, sql, values(params))

DBInterface.execute(conn::SQLConnection, sql::Union{AbstractSQLNode, AbstractSQLClause}, params) =
    DBInterface.execute(DBInterface.prepare(conn, sql), params)

DBInterface.close!(conn::SQLConnection) =
    DBInterface.close!(conn.raw)

DBInterface.execute(stmt::SQLStatement, params) =
    DBInterface.execute(stmt.raw, pack(stmt.vars, params))

DBInterface.getconnection(stmt::SQLStatement) =
    stmt.conn

DBInterface.close!(stmt::SQLStatement) =
    DBInterface.close(stmt.raw)

