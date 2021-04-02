# SQL Nodes

    using FunSQL:
        As, Call, From, Get, Literal, SQLTable, Select, Where, render, resolve

We start with specifying the database model.

    person = SQLTable(:person, columns = [:person_id, :year_of_birth])

In FunSQL, a SQL query is generated from a tree of `SQLNode` objects.  The
nodes are created using constructors with familiar SQL names and connected
together using the chain (`|>`) operator.

    q = From(person) |>
        Where(Call(">", Get.year_of_birth, 2000)) |>
        Select(Get.person_id)
    #-> (…) |> Select(…)

Displaying a `SQLNode` object shows how it was constructed.

    display(q)
    #=>
    From(SQLTable(:person, …)) |>
    Where(Call(">", Get.year_of_birth, Literal(2000))) |>
    Select(Get.person_id)
    =#

Each node wraps a concrete node object, which can be accessed using the
indexing operator.

    q[]
    #-> (…) |> SelectNode(…)

The SQL query is generated using the function `render()`.

    print(render(q))
    #=>
    SELECT "person_3"."person_id"
    FROM (
      SELECT "person_2"."person_id"
      FROM (
        SELECT "person_1"."person_id", "person_1"."year_of_birth"
        FROM "person" AS "person_1"
      ) AS "person_2"
      WHERE ("person_2"."year_of_birth" > 2000)
    ) AS "person_3"
    =#


## Literals

A SQL value is created with `Literal()` constructor.

    e = Literal("SQL is fun!")
    #-> Literal("SQL is fun!")

    e[]
    #-> LiteralNode("SQL is fun!")

In a `SELECT` clause, bare literal expressions get an alias `"_"`.

    q = Select(e)

    print(render(q))
    #=>
    SELECT 'SQL is fun!' AS "_"
    FROM (
      SELECT TRUE
    ) AS "__1"
    =#

Values of certain Julia data types are automatically converted to SQL
literals when they are used in the context of a SQL node.

    using Dates

    q = Select("null" => missing,
               "boolean" => true,
               "integer" => 42,
               "text" => "SQL is fun!",
               "date" => Date(2000))


## Attributes

To reference a table attribute, we use the `Get` constructor.

    e = Get(:person_id)
    #-> Get.person_id

    e[]
    #-> GetNode(:person_id)

Alternatively, use shorthand notation.

    Get.person_id
    #-> Get.person_id

    Get."person_id"
    #-> Get.person_id

    Get[:person_id]
    #-> Get.person_id

    Get["person_id"]
    #-> Get.person_id

`Get` can also create bound references.

    q = From(person)

    e = Get(over = q, :person_id)
    #-> (…) |> Get.person_id

    display(e)
    #-> From(SQLTable(:person, …)) |> Get.person_id

    q.person_id
    #-> (…) |> Get.person_id

    q."person_id"
    #-> (…) |> Get.person_id

    q[:person_id]
    #-> (…) |> Get.person_id

    q["person_id"]
    #-> (…) |> Get.person_id

`Get` is used for dereferencing an alias created with `As`.

    q = From(person) |>
        As(:p) |>
        Select(Get.p.person_id)

    print(render(q))
    #=>
    SELECT "p_1"."person_id"
    FROM (
      SELECT "person_1"."person_id"
      FROM "person" AS "person_1"
    ) AS "p_1"
    =#


## Operations

A function or an operator invocation is created with the `Call` constructor.

    e = Call(">", Get.year_of_birth, 2000)
    #-> Call(">", …)

    display(e)
    #-> Call(">", Get.year_of_birth, Literal(2000))

    e[]
    #-> CallNode(">", …)


## `As`

The `As` constructor is used to add an alias to attributes and subqueries.

    e = 42 |> As(:integer)
    #-> (…) |> As(:integer)

    display(e)
    #-> Literal(42) |> As(:integer)

    e[]
    #-> (…) |> AsNode(:integer)


## `From`

The `From` constructor creates a subquery that selects columns from the
given table.

    q = From(person)
    #-> From(…)

    display(q)
    #-> From(SQLTable(:person, …))

    q[]
    #-> FromNode(…)

By default, `From` selects all columns from the table.

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#


## `Select`

The `Select` constructor creates a subquery that fixes the output columns.

    q = From(person) |>
        Select(Get.person_id)
    #-> (…) |> Select(…)

    display(q)
    #-> From(SQLTable(:person, …)) |> Select(Get.person_id)

    q[]
    #-> (…) |> SelectNode(…)

    print(render(q))
    #=>
    SELECT "person_2"."person_id"
    FROM (
      SELECT "person_1"."person_id"
      FROM "person" AS "person_1"
    ) AS "person_2"
    =#


## `Where`

The `Where` constructor creates a subquery that filters by the given condition.

    q = From(person) |>
        Where(Call(">", Get.year_of_birth, 2000))
    #-> (…) |> Where(…)

    display(q)
    #=>
    From(SQLTable(:person, …)) |>
    Where(Call(">", Get.year_of_birth, Literal(2000)))
    =#

    q[]
    #-> (…) |> WhereNode(…)

    print(render(q))
    #=>
    SELECT "person_2"."person_id", "person_2"."year_of_birth"
    FROM (
      SELECT "person_1"."person_id", "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    WHERE ("person_2"."year_of_birth" > 2000)
    =#

