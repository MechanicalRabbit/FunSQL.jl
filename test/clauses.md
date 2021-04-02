# SQL Clauses

    using FunSQL: AS, ID, LITERAL, FROM, SELECT, WHERE, render

The syntactic structure of a SQL query is represented as a tree of `SQLClause`
objects.  Different types of clauses are created by specialized constructors
and connected using the chain (`|>`) operator.

    c = FROM(:person) |>
        SELECT(:person_id, :year_of_birth)
    #-> (…) |> SELECT(…)

Displaying a `SQLClause` object shows how it was constructed.

    display(c)
    #-> ID(:person) |> FROM() |> SELECT(ID(:person_id), ID(:year_of_birth))

A `SQLClause` object wraps a concrete clause object, which can be accessed
using the indexing operator.

    c[]
    #-> (…) |> SelectClause(…)

To generate SQL, we use function `render()`.

    print(render(c))
    #=>
    SELECT "person_id", "year_of_birth"
    FROM "person"
    =#


## SQL Literals

A SQL literal is created using a `LITERAL()` constructor.

    c = LITERAL("SQL is fun!")
    #-> LITERAL(…)

    display(c)
    #-> LITERAL("SQL is fun!")

    c[]
    #-> LiteralClause("SQL is fun!")

Values of certain Julia data types are automatically converted to SQL
literals when they are used in the context of a SQL clause.

    c = SELECT(missing, true, 42, "SQL is fun!")
    display(c)
    #-> SELECT(LITERAL(missing), LITERAL(true), LITERAL(42), LITERAL("SQL is fun!"))

    print(render(c))
    #-> SELECT NULL, TRUE, 42, 'SQL is fun!'

## SQL Identifiers

A SQL identifier is created with `ID()` constructor.

    c = ID(:person)
    #-> ID(:person)

    display(c)
    #-> ID(:person)

    c[]
    #-> IdentifierClause(:person)

    print(render(c))
    #-> "person"

A quoted identifier is created using pipeline notation.

    c = ID(:person) |> ID(:year_of_birth)
    #-> (…) |> ID(:year_of_birth)

    display(c)
    #-> ID(:person) |> ID(:year_of_birth)

    c[]
    #-> (…) |> IdentifierClause(:year_of_birth)

    print(render(c))
    #-> "person"."year_of_birth"

Symbols and pairs of symbols are automatically converted to SQL identifiers
when they are used in the context of a SQL clause.

    c = FROM(:p => :person) |> SELECT((:p, :person_id))
    display(c)
    #-> ID(:person) |> AS(:p) |> FROM() |> SELECT(ID(:p) |> ID(:person_id))

    print(render(c))
    #=>
    SELECT "p"."person_id"
    FROM "person" AS "p"
    =#


## `AS` Clause

An `AS` clause is created with `AS()` constructor.

    c = ID(:person) |> AS(:p)
    #-> (…) |> AS(:p)

    display(c)
    #-> ID(:person) |> AS(:p)

    c[]
    #-> (…) |> AsClause(:p)

    print(render(c))
    #-> "person" AS "p"

A pair expression is automatically converted to an `AS` clause.

    c = FROM(:p => :person)
    display(c)
    #-> ID(:person) |> AS(:p) |> FROM()

    print(render(c))
    #=>

    FROM "person" AS "p"
    =#


## `FROM` Clause

A `FROM` clause is created with `FROM()` constructor.

    c = FROM(:person)
    #-> (…) |> FROM()

    display(c)
    #-> ID(:person) |> FROM()

    c[]
    #-> (…) |> FromClause()

    print(render(c))
    #=>

    FROM "person"
    =#


## `SELECT` Clause

A `SELECT` clause is created with `SELECT()` constructor.  While in SQL,
`SELECT` typically opens a query, in FunSQL, `SELECT()` should be placed
at the end of a clause chain.

    c = FROM(:person) |> SELECT(:person_id, :year_of_birth)
    #-> (…) |> SELECT(…)

    display(c)
    #-> ID(:person) |> FROM() |> SELECT(ID(:person_id), ID(:year_of_birth))

    c[]
    #-> (…) |> SelectClause(…)

    print(render(c))
    #=>
    SELECT "person_id", "year_of_birth"
    FROM "person"
    =#


## `WHERE` Clause

A `WHERE` clause is created with `WHERE()` constructor.

    c = FROM(:person) |> WHERE(true)
    #-> (…) |> WHERE(…)

    display(c)
    #-> ID(:person) |> FROM() |> WHERE(LITERAL(true))

    c[]
    #-> (…) |> WhereClause(…)

    print(render(c))
    #=>

    FROM "person"
    WHERE TRUE
    =#

