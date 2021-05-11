# Properties of SQL dialects.

module VARIABLE_STYLE

@enum VariableStyle::UInt8 begin
    NAMED
    NUMBERED
    POSITIONAL
end

Base.convert(::Type{VariableStyle}, s::Symbol) =
    s in (:named, :NAMED) ?
        NAMED :
    s in (:numbered, :NUMBERED) ?
        NUMBERED :
    s in (:positional, :POSITIONAL) ?
        POSITIONAL :
    throw(DomainError(QuoteNode(s),
                      "expected :named, :numbered, or :positional"))

end

import .VARIABLE_STYLE.VariableStyle

"""
Properties of a SQL dialect.
"""
@Base.kwdef struct SQLDialect
    name::Symbol = :default
    variable_style::VariableStyle = VARIABLE_STYLE.NAMED
    variable_prefix::Char = ':'
end

SQLDialect(name::Symbol) =
    if name === :postgresql
        SQLDialect(name = name,
                   variable_style = VARIABLE_STYLE.NUMBERED,
                   variable_prefix = '$')
    elseif name === :sqlite
        SQLDialect(name = name,
                   variable_style = VARIABLE_STYLE.NUMBERED,
                   variable_prefix = '?')
    elseif name === :mysql
        SQLDialect(name = name,
                   variable_style = VARIABLE_STYLE.POSITIONAL,
                   variable_prefix = '?')
    elseif name === :redshift
        SQLDialect(name = name,
                   variable_style = VARIABLE_STYLE.NUMBERED,
                   variable_prefix = '$')
    elseif name === :sqlserver
        SQLDialect(name = name,
                   variable_style = VARIABLE_STYLE.POSITIONAL,
                   variable_prefix = '?')
    else
        SQLDialect()
    end

Base.show(io::IO, dialect::SQLDialect) =
    print(io, "SQLDialect($(QuoteNode(dialect.name)))")

Base.convert(::Type{SQLDialect}, name::Symbol) =
    SQLDialect(name)

