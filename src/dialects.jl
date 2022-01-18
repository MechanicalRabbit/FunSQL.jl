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

module LIMIT_STYLE

@enum LimitStyle::UInt8 begin
    ANSI
    MYSQL
    SQLITE
end

Base.convert(::Type{LimitStyle}, s::Symbol) =
    s in (:ansi, :ANSI) ?
        ANSI :
    s in (:mysql, :MYSQL) ?
        MYSQL :
    s in (:sqlite, :SQLITE) ?
        SQLITE :
    throw(DomainError(QuoteNode(s),
                      "expected :ansi, :mysql, or :sqlite"))

end

import .LIMIT_STYLE.LimitStyle

"""
    SQLDialect(; name = :default,
                 variable_style = :named,
                 variable_prefix = ':',
                 identifier_quotes = ('"', '"'),
                 has_boolean_literals = true,
                 limit_style = :ansi,
                 has_recursive_annotation = true,
                 values_row_constructor = nothing)
    SQLDialect(template::SQLDialect; kws...)
    SQLDialect(name::Symbol, kws...)
    SQLDialect(ConnType::Type)

Properties and capabilities of a particular SQL dialect.

Use `SQLDialect(name::Symbol)` to create one of the known dialects.
The following names are recognized:
* `:mysql`
* `:postgresql`
* `:redshift`
* `:sqlite`
* `:sqlserver`

Keyword parameters override individual properties of a dialect.

Use `SQLDialect(ConnType::Type)` to detect the dialect based on the type
of the database connection object.  The following types are recognized:
* `LibPQ.Connection`
* `MySQL.Connection`
* `SQLite.DB`

# Examples

```jldoctest
julia> postgresql_dialect = SQLDialect(:postgresql)
SQLDialect(:postgresql)

julia> postgresql_odbc_dialect = SQLDialect(:postgresql,
                                            variable_style = :positional,
                                            variable_prefix = '?')
SQLDialect(:postgresql, variable_style = :POSITIONAL, variable_prefix = '?')
```
"""
struct SQLDialect
    name::Symbol
    variable_style::VariableStyle
    variable_prefix::Char
    identifier_quotes::Tuple{Char, Char}
    has_boolean_literals::Bool
    limit_style::LimitStyle
    has_recursive_annotation::Bool
    has_as_columns::Bool
    values_row_constructor::Union{Symbol, Nothing}
    values_column_prefix::Union{Symbol, Nothing}
    values_column_index::Int

    SQLDialect(;
               name = :default,
               variable_style = VARIABLE_STYLE.NAMED,
               variable_prefix = ':',
               identifier_quotes = ('"', '"'),
               has_boolean_literals = true,
               limit_style = LIMIT_STYLE.ANSI,
               has_recursive_annotation = true,
               has_as_columns = true,
               values_row_constructor = nothing,
               values_column_prefix = :column,
               values_column_index = 1) =
        new(name,
            variable_style,
            variable_prefix,
            identifier_quotes,
            has_boolean_literals,
            limit_style,
            has_recursive_annotation,
            has_as_columns,
            values_row_constructor,
            values_column_prefix,
            values_column_index)
end

const default_dialect =
    SQLDialect()
const mysql_dialect =
    SQLDialect(name = :mysql,
               variable_style = VARIABLE_STYLE.POSITIONAL,
               variable_prefix = '?',
               identifier_quotes = ('`', '`'),
               limit_style = LIMIT_STYLE.MYSQL,
               values_row_constructor = :ROW,
               values_column_prefix = :column_,
               values_column_index = 0)
const postgresql_dialect =
    SQLDialect(name = :postgresql,
               variable_style = VARIABLE_STYLE.NUMBERED,
               variable_prefix = '$')
const redshift_dialect =
    SQLDialect(name = :redshift,
               variable_style = VARIABLE_STYLE.NUMBERED,
               variable_prefix = '$')
const sqlite_dialect =
    SQLDialect(name = :sqlite,
               variable_style = VARIABLE_STYLE.NUMBERED,
               variable_prefix = '?',
               limit_style = LIMIT_STYLE.SQLITE,
               has_as_columns = false)
const sqlserver_dialect =
    SQLDialect(name = :sqlserver,
               variable_style = VARIABLE_STYLE.POSITIONAL,
               variable_prefix = '?',
               identifier_quotes = ('[', ']'),
               has_boolean_literals = false,
               has_recursive_annotation = false,
               values_column_prefix = nothing)
const standard_dialects = [
    mysql_dialect,
    postgresql_dialect,
    redshift_dialect,
    sqlite_dialect,
    sqlserver_dialect,
    default_dialect]

function SQLDialect(name::Symbol; kws...)
    for sd in standard_dialects
        if sd.name === name
            return SQLDialect(sd; kws...)
        end
    end
    return SQLDialect(name = name; kws...)
end

@eval begin
    SQLDialect(template::SQLDialect; kws...) =
        isempty(kws) ?
            template :
            SQLDialect($([Expr(:kw, f, :(get(kws, $(QuoteNode(f)), template.$f)))
                          for f in fieldnames(SQLDialect)]...))
end

const known_connection_types = [
    [:MySQL, :Connection] => :mysql,
    [:LibPQ, :Connection] => :postgresql,
    [:SQLite, :DB] => :sqlite,
]

function SQLDialect(@nospecialize ConnType::Type)
    typename = Symbol[Base.fullname(Base.parentmodule(ConnType))..., nameof(ConnType)]
    for (t, n) in known_connection_types
        if t == typename
            return SQLDialect(n)
        end
    end
    throw(DomainError(ConnType, "cannot infer SQLDialect from the connection type"))
end

Base.convert(::Type{SQLDialect}, name::Symbol) =
    SQLDialect(name)

@generated function Base.:(==)(d1::SQLDialect, d2::SQLDialect)
    exs = Expr[]
    for f in fieldnames(d1)
        push!(exs, :(isequal(d1.$f, d2.$f)))
    end
    Expr(:||, :(d1 === d2), Expr(:&&, exs...))
end

@generated function Base.hash(d::SQLDialect, h::UInt)
    ex = :(h + $(hash(d)))
    for f in fieldnames(d)
        ex = :(hash(d.$f, $ex))
    end
    ex
end

function PrettyPrinting.quoteof(d::SQLDialect)
    ex = Expr(:call, nameof(SQLDialect))
    if d == default_dialect
        return ex
    end
    template = default_dialect
    for sd in standard_dialects
        if sd.name === d.name
            template = sd
            break
        end
    end
    if d.name === template.name
        push!(ex.args, QuoteNode(d.name))
    end
    for f in fieldnames(SQLDialect)
        v = getfield(d, f)
        if v != getfield(template, f)
            push!(ex.args, Expr(:kw, f, quoteof(v isa Enum ? Symbol(v) : v)))
        end
    end
    ex
end

function Base.show(io::IO, d::SQLDialect)
    if d == default_dialect
        return print(io, "SQLDialect()")
    end
    for sd in standard_dialects
        if sd == d
            return print(io, "SQLDialect($(QuoteNode(d.name)))")
        elseif sd.name === d.name
            return print(io, "SQLDialect($(QuoteNode(d.name)), …)")
        end
    end
    print(io, "SQLDialect(name = $(QuoteNode(d.name)), …)")
end

Base.show(io::IO, ::MIME"text/plain", d::SQLDialect) =
    pprint(io, d)

