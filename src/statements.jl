# Prepared SQL statement.

"""
Prepared SQL statement.
"""
@Base.kwdef struct SQLStatement <: AbstractString
    sql::String
    dialect::SQLDialect
    vars::Vector{Symbol}
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

"""
    pack(stmt::SQLStatement, vars::Union{Dict, NamedTuple}) :: Vector{Any}

Convert named parameters to positional form.
"""
function pack
end

pack(stmt::SQLStatement, d::AbstractDict{Symbol}) =
    Any[d[var] for var in stmt.vars]

pack(stmt::SQLStatement, d::AbstractDict{<:AbstractString}) =
    Any[d[String(var)] for var in stmt.vars]

pack(stmt::SQLStatement, nt::NamedTuple) =
    Any[getproperty(nt, var) for var in stmt.vars]

