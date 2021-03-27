# Properties of SQL dialects.

"""
Properties of a SQL dialect.
"""
struct SQLDialect
    name::Symbol
end

Base.convert(::Type{SQLDialect}, name::Symbol) =
    SQLDialect(name)

