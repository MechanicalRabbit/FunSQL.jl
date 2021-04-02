# SQL Nodes

    using FunSQL: As, Call, From, Get, SQLTable, Select, Where, render, resolve

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

