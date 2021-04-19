# Properties of SQL dialects.

"""
Properties of a SQL dialect.
"""
@Base.kwdef struct SQLDialect
    name::Symbol = :default
    has_window_clause::Bool = false
end

SQLDialect(name::Symbol) =
    if name === :postgresql
        SQLDialect(name = name, has_window_clause = true)
    elseif name === :sqlite
        SQLDialect(name = name, has_window_clause = true)
    elseif name === :mysql
        SQLDialect(name = name, has_window_clause = true)
    elseif name === :redshift
        SQLDialect(name = name)
    elseif name === :sqlserver
        SQLDialect(name = name)
    else
        SQLDialect()
    end

Base.show(io::IO, dialect::SQLDialect) =
    print(io, "SQLDialect(name = $(QuoteNode(dialect.name)), has_window_clause = $(dialect.has_window_clause))")

Base.convert(::Type{SQLDialect}, name::Symbol) =
    SQLDialect(name)

