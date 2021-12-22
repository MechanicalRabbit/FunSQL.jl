# SQL Dialects

In FunSQL, properties and capabilities of a particular SQL dialect
are encapsulated in a `SQLDialect` object.

    using FunSQL: SQLDialect

The desired dialect can be specified by name.

    postgresql_dialect = SQLDialect(:postgresql)
    #-> SQLDialect(:postgresql)

    display(postgresql_dialect)
    #-> SQLDialect(:postgresql)

If necessary, the dialect can be customized.

    postgresql_odbc_dialect = SQLDialect(:postgresql,
                                         variable_style = :positional,
                                         variable_prefix = '?')
    #-> SQLDialect(:postgresql, …)

    display(postgresql_odbc_dialect)
    #-> SQLDialect(:postgresql, variable_style = :POSITIONAL, variable_prefix = '?')

The default dialect does not correspond to any particular database server.

    default_dialect = SQLDialect()
    #-> SQLDialect()

    display(default_dialect)
    #-> SQLDialect()

A completely custom dialect can be specified.

    my_dialect = SQLDialect(:my, identifier_quotes = ('<', '>'))
    #-> SQLDialect(name = :my, …)

    display(my_dialect)
    #-> SQLDialect(name = :my, identifier_quotes = ('<', '>'))

