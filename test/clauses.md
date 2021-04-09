# SQL Clauses

    using FunSQL: AS, ID, KW, LIT, FROM, FUN, OP, SELECT, WHERE, render

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
    #-> ((…) |> SELECT(…))[]

    display(c[])
    #-> (ID(:person) |> FROM() |> SELECT(ID(:person_id), ID(:year_of_birth)))[]

To generate SQL, we use function `render()`.

    print(render(c))
    #=>
    SELECT "person_id", "year_of_birth"
    FROM "person"
    =#


## SQL Literals

A SQL literal is created using a `LIT()` constructor.

    c = LIT("SQL is fun!")
    #-> LIT("SQL is fun!")

Values of certain Julia data types are automatically converted to SQL
literals when they are used in the context of a SQL clause.

    using Dates

    c = SELECT(missing, true, 42, "SQL is fun!", Date(2000))

    #? VERSION >= v"1.5.0"
    display(c)
    #=>
    SELECT(LIT(missing),
           LIT(true),
           LIT(42),
           LIT("SQL is fun!"),
           LIT(Dates.Date("2000-01-01")))
    =#

    print(render(c))
    #-> SELECT NULL, TRUE, 42, 'SQL is fun!', '2000-01-01'


## SQL Identifiers

A SQL identifier is created with `ID()` constructor.

    c = ID(:person)
    #-> ID(:person)

    display(c)
    #-> ID(:person)

    print(render(c))
    #-> "person"

A quoted identifier is created using pipeline notation.

    c = ID(:person) |> ID(:year_of_birth)
    #-> (…) |> ID(:year_of_birth)

    display(c)
    #-> ID(:person) |> ID(:year_of_birth)

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


## SQL Functions

An application of a SQL function is created with `FUN()` constructor.

    c = FUN("CONCAT", :city, ", ", :state)
    #-> FUN("CONCAT", …)

    display(c)
    #-> FUN("CONCAT", ID(:city), LIT(", "), ID(:state))

    print(render(c))
    #-> CONCAT("city", ', ', "state")

A function with special separators can be constructed using `KW()` clause.

    c = FUN("SUBSTRING", :zip, KW("FROM", 1), KW("FOR", 3))
    #-> FUN("SUBSTRING", …)

    display(c)
    #-> FUN("SUBSTRING", ID(:zip), LIT(1) |> KW(:FROM), LIT(3) |> KW(:FOR))

    print(render(c))
    #-> SUBSTRING("zip" FROM 1 FOR 3)

Functions without arguments are permitted.

    c = FUN("NOW")
    #-> FUN("NOW")

    print(render(c))
    #-> NOW()


## SQL Operators

An application of a SQL operator is created with `OP()` constructor.

    c = OP("NOT", OP("=", :zip, "60614"))
    #-> OP("NOT", …)

    display(c)
    #-> OP("NOT", OP("=", ID(:zip), LIT("60614")))

    print(render(c))
    #-> (NOT ("zip" = '60614'))

An operator without arguments can be constructed, if necessary.

    c = OP("CURRENT_TIMESTAMP")
    #-> OP("CURRENT_TIMESTAMP")

    print(render(c))
    #-> CURRENT_TIMESTAMP

A composite operator can be constructed with the help of `KW()` clause.

    c = OP("BETWEEN", :year_of_birth, 2000, KW(:AND, 2020))

    print(render(c))
    #-> ("year_of_birth" BETWEEN 2000 AND 2020)


## `AS` Clause

An `AS` clause is created with `AS()` constructor.

    c = ID(:person) |> AS(:p)
    #-> (…) |> AS(:p)

    display(c)
    #-> ID(:person) |> AS(:p)

    print(render(c))
    #-> "person" AS "p"

A pair expression is automatically converted to an `AS` clause.

    c = FROM(:p => :person)
    display(c)
    #-> ID(:person) |> AS(:p) |> FROM()

    print(render(c |> SELECT((:p, :person_id))))
    #=>
    SELECT "p"."person_id"
    FROM "person" AS "p"
    =#


## `FROM` Clause

A `FROM` clause is created with `FROM()` constructor.

    c = FROM(:person)
    #-> (…) |> FROM()

    display(c)
    #-> ID(:person) |> FROM()

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    =#


## `SELECT` Clause

A `SELECT` clause is created with `SELECT()` constructor.  While in SQL,
`SELECT` typically opens a query, in FunSQL, `SELECT()` should be placed
at the end of a clause chain.

    c = :person |> FROM() |> SELECT(:person_id, :year_of_birth)
    #-> (…) |> SELECT(…)

    display(c)
    #-> ID(:person) |> FROM() |> SELECT(ID(:person_id), ID(:year_of_birth))

    print(render(c))
    #=>
    SELECT "person_id", "year_of_birth"
    FROM "person"
    =#

The `DISTINCT` modifier can be added from the constructor.

    c = FROM(:location) |> SELECT(distinct = true, :zip)
    #-> (…) |> SELECT(…)

    display(c)
    #-> ID(:location) |> FROM() |> SELECT(distinct = true, ID(:zip))

    print(render(c))
    #=>
    SELECT DISTINCT "zip"
    FROM "location"
    =#

A `SELECT` clause with an empty list can be created explicitly.

    c = SELECT(list = [])
    #-> SELECT(…)

Rendering a nested `SELECT` clause adds parentheses around it.

    c = :location |> FROM() |> SELECT(:state, :zip) |> FROM() |> SELECT(:zip)

    print(render(c))
    #=>
    SELECT "zip"
    FROM (
      SELECT "state", "zip"
      FROM "location"
    )
    =#


## `WHERE` Clause

A `WHERE` clause is created with `WHERE()` constructor.

    c = FROM(:person) |> WHERE(OP(">", :year_of_birth, 2000))
    #-> (…) |> WHERE(…)

    display(c)
    #-> ID(:person) |> FROM() |> WHERE(OP(">", ID(:year_of_birth), LIT(2000)))

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE ("year_of_birth" > 2000)
    =#

