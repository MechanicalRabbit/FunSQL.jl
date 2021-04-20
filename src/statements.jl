# Prepared SQL statement.

"""
Prepared SQL statement.
"""
@Base.kwdef struct SQLStatement <: AbstractString
    sql::String
    dialect::SQLDialect
end

Base.ncodeunits(stmt::SQLStatement) =
    ncodeunits(stmt.sql)

Base.codeunit(stmt::SQLStatement) =
    codeunit(stmt.sql)

@Base.propagate_inbounds Base.codeunit(stmt::SQLStatement, i::Integer) =
    codeunit(stmt.sql, i)

@Base.propagate_inbounds Base.isvalid(stmt::SQLStatement, i::Integer) =
    isvalid(stmt.sql, i)

@Base.propagate_inbounds Base.iterate(stmt::SQLStatement, i::Integer = 1) =
    iterate(stmt.sql, i)

Base.String(stmt::SQLStatement) =
    stmt.sql

Base.print(io::IO, stmt::SQLStatement) =
    print(io, stmt.sql)

Base.write(io::IO, stmt::SQLStatement) =
    write(io, stmt.sql)

