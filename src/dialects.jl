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
    POSTGRESQL
    SQLITE
    SQLSERVER
end

Base.convert(::Type{LimitStyle}, s::Symbol) =
    s in (:ansi, :ANSI) ?
        ANSI :
    s in (:mysql, :MYSQL) ?
        MYSQL :
    s in (:postgresql, :POSTGRESQL) ?
        POSTGRESQL :
    s in (:sqlite, :SQLITE) ?
        SQLITE :
    s in (:sqlserver, :SQLSERVER) ?
        SQLSERVER :
    throw(DomainError(QuoteNode(s),
                      "expected :ansi, :mysql, :postgresql, :sqlite, or :sqlserver"))

end

import .LIMIT_STYLE.LimitStyle

"""
    SQLDialect(; name = :default, kws...)
    SQLDialect(template::SQLDialect; kws...)
    SQLDialect(name::Symbol, kws...)
    SQLDialect(ConnType::Type)

Properties and capabilities of a particular SQL dialect.

Use `SQLDialect(name::Symbol)` to create one of the known dialects.
The following names are recognized:
* `:mysql`
* `:postgresql`
* `:redshift`
* `:spark`
* `:sqlite`
* `:sqlserver`

Keyword parameters override individual properties of a dialect.  For details,
check the source code.

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
                                            variable_prefix = '?',
                                            variable_style = :positional)
SQLDialect(:postgresql, variable_prefix = '?', variable_style = :POSITIONAL)
```
"""
struct SQLDialect
    name::Symbol
    concat_operator::Union{Symbol, Nothing}
    has_as_columns::Bool
    has_boolean_literals::Bool
    has_implicit_lateral::Bool
    has_recursive_annotation::Bool
    identifier_quotes::Tuple{Char, Char}
    is_backslash_literal::Bool
    limit_style::LimitStyle
    values_column_index::Int
    values_column_prefix::Union{Symbol, Nothing}
    values_row_constructor::Union{Symbol, Nothing}
    variable_prefix::Char
    variable_style::VariableStyle

    SQLDialect(;
               name = :default,
               concat_operator = nothing,
               has_as_columns = true,
               has_boolean_literals = true,
               has_implicit_lateral = true,
               has_recursive_annotation = true,
               identifier_quotes = ('"', '"'),
               is_backslash_literal = true,
               limit_style = LIMIT_STYLE.ANSI,
               values_column_index = 1,
               values_column_prefix = :column,
               values_row_constructor = nothing,
               variable_prefix = ':',
               variable_style = VARIABLE_STYLE.NAMED) =
        new(name,
            concat_operator,
            has_as_columns,
            has_boolean_literals,
            has_implicit_lateral,
            has_recursive_annotation,
            identifier_quotes,
            is_backslash_literal,
            limit_style,
            values_column_index,
            values_column_prefix,
            values_row_constructor,
            variable_prefix,
            variable_style)
end

const default_dialect =
    SQLDialect()
const mysql_dialect =
    SQLDialect(name = :mysql,
               identifier_quotes = ('`', '`'),
               limit_style = LIMIT_STYLE.MYSQL,
               values_column_index = 0,
               values_column_prefix = :column_,
               values_row_constructor = :ROW,
               variable_prefix = '?',
               variable_style = VARIABLE_STYLE.POSITIONAL)
const postgresql_dialect =
    SQLDialect(name = :postgresql,
               limit_style = LIMIT_STYLE.POSTGRESQL,
               variable_prefix = '$',
               variable_style = VARIABLE_STYLE.NUMBERED)
const duckdb_dialect =
    SQLDialect(name = :duckdb,
               limit_style = LIMIT_STYLE.POSTGRESQL,
               variable_prefix = '$',
               variable_style = VARIABLE_STYLE.NUMBERED)
const redshift_dialect =
    SQLDialect(name = :redshift,
               concat_operator = Symbol("||"),
               limit_style = LIMIT_STYLE.POSTGRESQL,
               variable_prefix = '$',
               variable_style = VARIABLE_STYLE.NUMBERED)
const spark_dialect =
    SQLDialect(name = :spark,
               has_implicit_lateral = false,
               identifier_quotes = ('`', '`'),
               limit_style = LIMIT_STYLE.POSTGRESQL,
               is_backslash_literal = false,
               values_column_prefix = :col)
const sqlite_dialect =
    SQLDialect(name = :sqlite,
               concat_operator = Symbol("||"),
               has_as_columns = false,
               limit_style = LIMIT_STYLE.SQLITE,
               variable_prefix = '?',
               variable_style = VARIABLE_STYLE.NUMBERED)
const sqlserver_dialect =
    SQLDialect(name = :sqlserver,
               has_boolean_literals = false,
               has_recursive_annotation = false,
               identifier_quotes = ('[', ']'),
               limit_style = LIMIT_STYLE.SQLSERVER,
               values_column_prefix = nothing,
               variable_prefix = '?',
               variable_style = VARIABLE_STYLE.POSITIONAL)
const standard_dialects = [
    mysql_dialect,
    postgresql_dialect,
    redshift_dialect,
    spark_dialect,
    sqlite_dialect,
    sqlserver_dialect,
    default_dialect,
    duckdb_dialect]

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
    [:DuckDB, :DB] => :duckdb,
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

