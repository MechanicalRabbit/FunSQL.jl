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
                 limit_style = :ansi)
    SQLDialect(template::SQLDialect; kws...)
    SQLDialect(name::Symbol, kws...)

Properties and capabilities of a particular SQL dialect.

Use the constructor `SQLDialect(name::Symbol)` to create one of the known
dialects: `:postgresql`, `:sqlite`, `:mysql`, `:redshift`, `:sqlserver`.
"""
struct SQLDialect
    name::Symbol
    variable_style::VariableStyle
    variable_prefix::Char
    identifier_quotes::Tuple{Char, Char}
    has_boolean_literals::Bool
    limit_style::LimitStyle

    SQLDialect(;
               name = :default,
               variable_style = VARIABLE_STYLE.NAMED,
               variable_prefix = ':',
               identifier_quotes = ('"', '"'),
               has_boolean_literals = true,
               limit_style = LIMIT_STYLE.ANSI) =
        new(name,
            variable_style,
            variable_prefix,
            identifier_quotes,
            has_boolean_literals,
            limit_style)
end

const default_dialect =
    SQLDialect()
const mysql_dialect =
    SQLDialect(name = :mysql,
               variable_style = VARIABLE_STYLE.POSITIONAL,
               variable_prefix = '?',
               identifier_quotes = ('`', '`'),
               limit_style = LIMIT_STYLE.MYSQL)
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
               limit_style = LIMIT_STYLE.SQLITE)
const sqlserver_dialect =
    SQLDialect(name = :sqlserver,
               variable_style = VARIABLE_STYLE.POSITIONAL,
               variable_prefix = '?',
               identifier_quotes = ('[', ']'),
               has_boolean_literals = false)
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

