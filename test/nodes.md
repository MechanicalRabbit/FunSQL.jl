# SQL Nodes

    using FunSQL:
        As, Call, From, Get, Literal, SQLNode, SQLTable, Select, Where, render,
        resolve

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
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Call(">", Get.year_of_birth, Literal(2000))),
        q3 = q2 |> Select(Get.person_id)
        q3
    end
    =#

Each node wraps a concrete node object, which can be accessed using the
indexing operator.

    q[]
    #-> ((…) |> Select(…))[]

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

Alternatively, use shorthand notation.

    Get.person_id
    #-> Get.person_id

    Get."person_id"
    #-> Get.person_id

    Get[:person_id]
    #-> Get.person_id

    Get["person_id"]
    #-> Get.person_id

Hierarchical notation is supported.

    e = Get.p.person_id
    #-> Get.p.person_id

    Get.p |> Get.person_id
    #-> Get.p.person_id

`Get` can also create bound references.

    q = From(person)

    e = Get(over = q, :year_of_birth)
    #-> (…) |> Get.year_of_birth

    display(e)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person)
        q1.year_of_birth
    end
    =#

    q = q |> Where(Call(">", e, 2000))

    e = Get(over = q, :person_id)
    #-> (…) |> Get.person_id

    q.person_id
    #-> (…) |> Get.person_id

    q."person_id"
    #-> (…) |> Get.person_id

    q[:person_id]
    #-> (…) |> Get.person_id

    q["person_id"]
    #-> (…) |> Get.person_id

    q = q |> Select(e)

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

When `Get` refers to an unknown attribute, an error is reported.

    q = Select(Get.person_id)

    print(render(q))
    #=>
    ERROR: GetError: cannot find person_id in:
    Select(Get.person_id)
    =#

    q = From(person) |>
        As(:p) |>
        Select(Get.q.person_id)

    print(render(q))
    #=>
    ERROR: GetError: cannot find person_id in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> As(:p) |> Select(Get.q.person_id)
        q2
    end
    =#


## Operations

A function or an operator invocation is created with the `Call` constructor.

    e = Call(">", Get.year_of_birth, 2000)
    #-> Call(">", …)

    display(e)
    #-> Call(">", Get.year_of_birth, Literal(2000))

A vector of arguments could be passed directly.

    Call(">", args = SQLNode[Get.year_of_birth, 2000])
    #-> Call(">", …)

In a `SELECT` clause, operator calls get an alias from their name.

    print(render(From(person) |> Select(e)))
    #=>
    SELECT ("person_2"."year_of_birth" > 2000) AS ">"
    FROM (
      SELECT "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    =#


## `As`

An alias to an expression can be added with the `As` constructor.

    e = 42 |> As(:integer)
    #-> (…) |> As(:integer)

    display(e)
    #-> Literal(42) |> As(:integer)

    print(render(Select(e)))
    #=>
    SELECT 42 AS "integer"
    FROM (
      SELECT TRUE
    ) AS "__1"
    =#

`As` is also used to create an alias for a subquery.

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

`As` blocks the default output columns.

    q = From(person) |> As(:p)

    print(render(q))
    #=>
    SELECT TRUE
    FROM "person" AS "person_1"
    =#


## `From`

The `From` constructor creates a subquery that selects columns from the
given table.

    q = From(person)
    #-> From(…)

    display(q)
    #-> From(SQLTable(:person, …))

By default, `From` selects all columns from the table.

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#

`From` adds the schema qualifier when the table has the schema.

    concept = SQLTable(schema = :public,
                       :concept,
                       columns = [:concept_id, :description])

    q = From(concept)

    print(render(q))
    #=>
    SELECT "concept_1"."concept_id", "concept_1"."description"
    FROM "public"."concept" AS "concept_1"
    =#

In a suitable context, a `SQLTable` object is automatically converted to a
`From` subquery.

    print(render(person))
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#

`From` and other subqueries generate a correct `SELECT` clause when the table
has no columns.

    empty = SQLTable(:empty, columns = Symbol[])

    q = From(empty) |>
        Where(true) |>
        Select(list = [])

    display(q)
    #=>
    let empty = SQLTable(:empty, …),
        q1 = From(empty),
        q2 = q1 |> Where(Literal(true)),
        q3 = q2 |> Select(list = [])
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT TRUE
    FROM (
      SELECT TRUE
      FROM (
        SELECT TRUE
        FROM "empty" AS "empty_1"
      ) AS "empty_2"
      WHERE TRUE
    ) AS "empty_3"
    =#


## `Select`

The `Select` constructor creates a subquery that fixes the output columns.

    q = From(person) |>
        Select(Get.person_id)
    #-> (…) |> Select(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Select(Get.person_id)
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_2"."person_id"
    FROM (
      SELECT "person_1"."person_id"
      FROM "person" AS "person_1"
    ) AS "person_2"
    =#

`Select` does not have to be the last subquery in a chain.

    q = From(person) |>
        Select(Get.year_of_birth) |>
        Where(Call(">", Get.year_of_birth, 2000))

    print(render(q))
    #=>
    SELECT "person_3"."year_of_birth"
    FROM (
      SELECT "person_2"."year_of_birth"
      FROM (
        SELECT "person_1"."year_of_birth"
        FROM "person" AS "person_1"
      ) AS "person_2"
    ) AS "person_3"
    WHERE ("person_3"."year_of_birth" > 2000)
    =#


## `Where`

The `Where` constructor creates a subquery that filters by the given condition.

    q = From(person) |>
        Where(Call(">", Get.year_of_birth, 2000))
    #-> (…) |> Where(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Call(">", Get.year_of_birth, Literal(2000)))
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_2"."person_id", "person_2"."year_of_birth"
    FROM (
      SELECT "person_1"."person_id", "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    WHERE ("person_2"."year_of_birth" > 2000)
    =#

