# SQL Nodes

    using FunSQL:
        Agg, Append, As, Bind, Define, Fun, From, Get, Group, Highlight, Join,
        LeftJoin, Lit, Partition, SQLNode, SQLTable, Select, Var, Where,
        render, resolve

We start with specifying the database model.


    const concept =
        SQLTable(:concept, columns = [:concept_id, :vocabulary_id, :concept_code])

    const location =
        SQLTable(:location, columns = [:location_id, :city, :state])

    const person =
        SQLTable(:person, columns = [:person_id, :gender_concept_id, :year_of_birth, :month_of_birth, :day_of_birth, :birth_datetime, :location_id])

    const visit_occurrence =
        SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date, :visit_end_date])

In FunSQL, a SQL query is generated from a tree of `SQLNode` objects.  The
nodes are created using constructors with familiar SQL names and connected
together using the chain (`|>`) operator.

    q = From(person) |>
        Where(Fun.">"(Get.year_of_birth, 2000)) |>
        Select(Get.person_id)
    #-> (…) |> Select(…)

Displaying a `SQLNode` object shows how it was constructed.

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, Lit(2000))),
        q3 = q2 |> Select(Get.person_id)
        q3
    end
    =#

Each node wraps a concrete node object, which can be accessed using the
indexing operator.

    q[]
    #-> ((…) |> Select(…))[]

    display(q[])
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, Lit(2000))),
        q3 = q2 |> Select(Get.person_id)
        q3[]
    end
    =#

The SQL query is generated using the function `render()`.

    print(render(q))
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 2000)
    =#


## Literals

A SQL value is created with `Lit()` constructor.

    e = Lit("SQL is fun!")
    #-> Lit("SQL is fun!")

In a `SELECT` clause, bare literal expressions get an alias `"_"`.

    q = Select(e)

    print(render(q))
    #=>
    SELECT 'SQL is fun!' AS "_"
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

    q = q |> Where(Fun.">"(e, 2000))

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
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 2000)
    =#

`Get` is used for dereferencing an alias created with `As`.

    q = From(person) |>
        As(:p) |>
        Select(Get.p.person_id)

    print(render(q))
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
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

An error is also reported when a `Get` reference cannot be resolved
unambiguously.

    q = person |>
        Join(person, true) |>
        Select(Get.person_id)

    print(render(q))
    #=>
    ERROR: GetError: ambiguous person_id in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = From(person),
        q3 = q1 |> Join(q2, Lit(true)),
        q4 = q3 |> Select(Get.person_id)
        q4
    end
    =#

Any expression could be given a name and attached to a query using the `Define`
constructor.

    q = From(person) |>
        Define(:age => Fun.now() .- Get.birth_datetime)
    #-> (…) |> Define(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Define(Fun."-"(Fun.now(), Get.birth_datetime) |> As(:age))
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

This expression could be referred to by name as if it were a regular table
attribute.

    print(render(q |> Where(Get.age .> "16 years")))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ((NOW() - "person_1"."birth_datetime") > '16 years')
    =#


## Variables

A query variable is created with the `Var` constructor.

    e = Var(:year)
    #-> Var.year

Alternatively, use shorthand notation.

    Var.year
    #-> Var.year

    Var."year"
    #-> Var.year

    Var[:year]
    #-> Var.year

    Var["year"]
    #-> Var.year

Unbound query variables are serialized as query parameters.

    q = From(person) |>
        Where(Get.year_of_birth .> Var.year)

    sql = render(q)

    print(sql)
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > :year)
    =#

    sql.vars
    #-> [:year]

Query variables could be bound using the `Bind` constructor.

    q0(person_id) =
        From(visit_occurrence) |>
        Where(Get.person_id .== Var.person_id) |>
        Bind(:person_id => person_id)

    q0(1)
    #-> (…) |> Bind(…)

    display(q0(1))
    #=>
    let visit_occurrence = SQLTable(:visit_occurrence, …),
        q1 = From(visit_occurrence),
        q2 = q1 |> Where(Fun."=="(Get.person_id, Var.person_id))
        q2 |> Bind(Lit(1) |> As(:person_id))
    end
    =#

    print(render(q0(1)))
    #=>
    SELECT "visit_occurrence_1"."visit_occurrence_id", …, "visit_occurrence_1"."visit_end_date"
    FROM "visit_occurrence" AS "visit_occurrence_1"
    WHERE ("visit_occurrence_1"."person_id" = 1)
    =#

`Bind` lets us create correlated subqueries.

    q = From(person) |>
        Where(Fun.exists(q0(Get.person_id)))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (EXISTS (
      SELECT TRUE
      FROM "visit_occurrence" AS "visit_occurrence_1"
      WHERE ("visit_occurrence_1"."person_id" = "person_1"."person_id")
    ))
    =#

An empty `Bind` can be created.

    Bind(list = [])
    #-> Bind(list = [])


## Functions and Operations

A function or an operator invocation is created with the `Fun` constructor.

    e = Fun.">"(Get.year_of_birth, 2000)
    #-> Fun.:(">")(…)

    display(e)
    #-> Fun.">"(Get.year_of_birth, Lit(2000))

A vector of arguments could be passed directly.

    Fun.">"(args = SQLNode[Get.year_of_birth, 2000])
    #-> Fun.:(">")(…)

In a `SELECT` clause, operator calls get an alias from their name.

    print(render(From(person) |> Select(e)))
    #=>
    SELECT ("person_1"."year_of_birth" > 2000) AS ">"
    FROM "person" AS "person_1"
    =#

A function invocation may include a nested query.

    p = From(person) |>
        Where(Get.year_of_birth .> 1950)

    q = Select(Fun.exists(p))

    print(render(q))
    #=>
    SELECT (EXISTS (
      SELECT TRUE
      FROM "person" AS "person_1"
      WHERE ("person_1"."year_of_birth" > 1950)
    )) AS "exists"
    =#

    p = From(concept) |>
        Where(Fun.and(Get.vocabulary_id .== "Gender",
                      Get.concept_code .== "F")) |>
        Select(Get.concept_id)

    q = From(person) |>
        Where(Fun.in(Get.gender_concept_id, p))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."gender_concept_id" IN (
      SELECT "concept_1"."concept_id"
      FROM "concept" AS "concept_1"
      WHERE (("concept_1"."vocabulary_id" = 'Gender') AND ("concept_1"."concept_code" = 'F'))
    ))
    =#


## `As`

An alias to an expression can be added with the `As` constructor.

    e = 42 |> As(:integer)
    #-> (…) |> As(:integer)

    display(e)
    #-> Lit(42) |> As(:integer)

    print(render(Select(e)))
    #=>
    SELECT 42 AS "integer"
    =#

`As` is also used to create an alias for a subquery.

    q = From(person) |>
        As(:p) |>
        Select(Get.p.person_id)

    print(render(q))
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
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
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

`From` adds the schema qualifier when the table has the schema.

    const pg_database =
        SQLTable(schema = :pg_catalog, :pg_database, columns = [:oid, :datname])

    q = From(pg_database)

    print(render(q))
    #=>
    SELECT "pg_database_1"."oid", "pg_database_1"."datname"
    FROM "pg_catalog"."pg_database" AS "pg_database_1"
    =#

In a suitable context, a `SQLTable` object is automatically converted to a
`From` subquery.

    print(render(person))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

`From` and other subqueries generate a correct `SELECT` clause when the table
has no columns.

    empty = SQLTable(:empty, columns = Symbol[])

    q = From(empty) |>
        Where(false) |>
        Select(list = [])

    display(q)
    #=>
    let empty = SQLTable(:empty, …),
        q1 = From(empty),
        q2 = q1 |> Where(Lit(false)),
        q3 = q2 |> Select(list = [])
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT TRUE
    FROM "empty" AS "empty_1"
    WHERE FALSE
    =#


## `Group`

The `Group` constructor creates a subquery that summarizes the rows partitioned
by the given keys.

    q = From(person) |>
        Group(Get.year_of_birth)
    #-> (…) |> Group(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.year_of_birth)
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT DISTINCT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#

Partitions created by `Group` are summarized using aggregate expressions.

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Select(Get.year_of_birth, Agg.count())

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth", COUNT(*) AS "count"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    =#

`Group` accepts an empty list of keys.

    q = From(person) |>
        Group() |>
        Select(Agg.count(), Agg.min(Get.year_of_birth), Agg.max(Get.year_of_birth))

    print(render(q))
    #=>
    SELECT COUNT(*) AS "count", MIN("person_1"."year_of_birth") AS "min", MAX("person_1"."year_of_birth") AS "max"
    FROM "person" AS "person_1"
    =#

`Group` with no keys and no aggregates creates a trivial subquery.

    q = From(person) |>
        Group()

    print(render(q))
    #-> SELECT TRUE

`Group` requires all keys to have unique aliases.

    q = From(person) |>
        Group(Get.person_id, Get.person_id)

    print(render(q))
    #=>
    ERROR: DuplicateAliasError: person_id in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.person_id, Get.person_id)
        q2
    end
    =#

`Group` ensures that each aggregate expression gets a unique alias.

    q = From(person) |>
        Join(:visit_group => From(visit_occurrence) |>
                             Group(Get.person_id),
             on = Get.person_id .== Get.visit_group.person_id) |>
        Select(Get.person_id,
               :max_visit_start_date =>
                   Get.visit_group |> Agg.max(Get.visit_start_date),
               :max_visit_end_date =>
                   Get.visit_group |> Agg.max(Get.visit_end_date))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "visit_group_1"."max_1" AS "max_visit_start_date", "visit_group_1"."max_2" AS "max_visit_end_date"
    FROM "person" AS "person_1"
    JOIN (
      SELECT "visit_occurrence_1"."person_id", MAX("visit_occurrence_1"."visit_start_date") AS "max_1", MAX("visit_occurrence_1"."visit_end_date") AS "max_2"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_group_1" ON ("person_1"."person_id" = "visit_group_1"."person_id")
    =#

Aggregate expressions can be applied to distinct values of the partition.

    e = Agg.count(distinct = true, Get.year_of_birth)
    #-> Agg.count(distinct = true, …)

    display(e)
    #-> Agg.count(distinct = true, Get.year_of_birth)

    q = From(person) |> Group() |> Select(e)

    print(render(q))
    #=>
    SELECT COUNT(DISTINCT "person_1"."year_of_birth") AS "count"
    FROM "person" AS "person_1"
    =#

Aggregate expressions can be applied to a filtered portion of a partition.

    e = Agg.count(filter = Get.year_of_birth .> 1950)
    #-> Agg.count(filter = (…))

    display(e)
    #-> Agg.count(filter = Fun.">"(Get.year_of_birth, Lit(1950)))

    q = From(person) |> Group() |> Select(e)

    print(render(q))
    #=>
    SELECT (COUNT(*) FILTER (WHERE ("person_1"."year_of_birth" > 1950))) AS "count"
    FROM "person" AS "person_1"
    =#


## `Partition`

The `Partition` constructor creates a subquery that partitions the rows by the
given keys.

    q = From(person) |>
        Partition(Get.year_of_birth, order_by = [Get.month_of_birth, Get.day_of_birth])
    #-> (…) |> Partition(…, order_by = […])

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |>
             Partition(Get.year_of_birth,
                       order_by = [Get.month_of_birth, Get.day_of_birth])
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

Calculations across the rows of the partitions are performed by window
functions.

    q = From(person) |>
        Partition(Get.gender_concept_id) |>
        Select(Get.person_id, Agg.row_number())

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Partition(Get.gender_concept_id),
        q3 = q2 |> Select(Get.person_id, Agg.row_number())
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", (ROW_NUMBER() OVER (PARTITION BY "person_1"."gender_concept_id")) AS "row_number"
    FROM "person" AS "person_1"
    =#

A partition may specify the window frame.

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Partition(order_by = [Get.year_of_birth],
                  frame = (mode = :range, start = -1, finish = 1)) |>
        Select(Get.year_of_birth, Agg.avg(Agg.count()))

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.year_of_birth),
        q3 = q2 |>
             Partition(order_by = [Get.year_of_birth],
                       frame = (mode = :RANGE, start = -1, finish = 1)),
        q4 = q3 |> Select(Get.year_of_birth, Agg.avg(Agg.count()))
        q4
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth", (AVG(COUNT(*)) OVER (ORDER BY "person_1"."year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING)) AS "avg"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    =#


## `Join`

The `Join` constructor creates a subquery that combines the rows of two
nested subqueries.

    q = From(person) |>
        Join(:location => From(location),
             on = Get.location_id .== Get.location.location_id,
             left = true)
    #-> (…) |> Join(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        location = SQLTable(:location, …),
        q1 = From(person),
        q2 = From(location),
        q3 = q1 |>
             Join(q2 |> As(:location),
                  Fun."=="(Get.location_id, Get.location.location_id),
                  left = true)
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    LEFT JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
    =#

`LEFT JOIN` is commonly used and has its own constructor.

    q = From(person) |>
        LeftJoin(:location => From(location),
                 on = Get.location_id .== Get.location.location_id)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        location = SQLTable(:location, …),
        q1 = From(person),
        q2 = From(location),
        q3 = q1 |>
             Join(q2 |> As(:location),
                  Fun."=="(Get.location_id, Get.location.location_id),
                  left = true)
        q3
    end
    =#

Nested subqueries that are combined with `Join` may fail to collapse.

    q = From(person) |>
        Where(Get.year_of_birth .> 1970) |>
        Join(:location => From(location) |>
                          Where(Get.state .== "IL"),
             on = (Get.location_id .== Get.location.location_id)) |>
        Select(Get.person_id, Get.location.city)

    print(render(q))
    #=>
    SELECT "person_3"."person_id", "location_3"."city"
    FROM (
      SELECT "person_1"."location_id", "person_1"."person_id"
      FROM "person" AS "person_1"
      WHERE ("person_1"."year_of_birth" > 1970)
    ) AS "person_3"
    JOIN (
      SELECT "location_1"."location_id", "location_1"."city"
      FROM "location" AS "location_1"
      WHERE ("location_1"."state" = 'IL')
    ) AS "location_3" ON ("person_3"."location_id" = "location_3"."location_id")
    =#

`Join` can be applied to correlated subqueries.

    q0(person_id) =
        From(visit_occurrence) |>
        Where(Get.person_id .== Var.person_id) |>
        Partition(order_by = [Get.visit_start_date]) |>
        Where(Agg.row_number() .== 1) |>
        Bind(:person_id => person_id)

    print(render(q0(1)))
    #=>
    SELECT "visit_occurrence_4"."visit_occurrence_id", …, "visit_occurrence_4"."visit_end_date"
    FROM (
      SELECT (ROW_NUMBER() OVER (ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number", "visit_occurrence_1"."visit_occurrence_id", …, "visit_occurrence_1"."visit_end_date"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      WHERE ("visit_occurrence_1"."person_id" = 1)
    ) AS "visit_occurrence_4"
    WHERE ("visit_occurrence_4"."row_number" = 1)
    =#

    q = From(person) |>
        Join(:visit => q0(Get.person_id), on = true) |>
        Select(Get.person_id,
               Get.visit.visit_occurrence_id,
               Get.visit.visit_start_date)

    print(render(q))
    #=>
    SELECT "person_2"."person_id", "visit_1"."visit_occurrence_id", "visit_1"."visit_start_date"
    FROM (
      SELECT "person_1"."person_id"
      FROM "person" AS "person_1"
    ) AS "person_2"
    CROSS JOIN LATERAL (
      SELECT "visit_occurrence_4"."visit_occurrence_id", "visit_occurrence_4"."visit_start_date"
      FROM (
        SELECT (ROW_NUMBER() OVER (ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number", "visit_occurrence_1"."visit_occurrence_id", "visit_occurrence_1"."visit_start_date"
        FROM "visit_occurrence" AS "visit_occurrence_1"
        WHERE ("visit_occurrence_1"."person_id" = "person_2"."person_id")
      ) AS "visit_occurrence_4"
      WHERE ("visit_occurrence_4"."row_number" = 1)
    ) AS "visit_1"
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
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    =#

`Select` does not have to be the last subquery in a chain.

    q = From(person) |>
        Select(Get.year_of_birth) |>
        Where(Fun.">"(Get.year_of_birth, 2000))

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 2000)
    =#

`Select` requires all columns in the list to have unique aliases.

    q = From(person) |>
        Select(Get.person_id, Get.person_id)

    print(render(q))
    #=>
    ERROR: DuplicateAliasError: person_id in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Select(Get.person_id, Get.person_id)
        q2
    end
    =#


## `Where`

The `Where` constructor creates a subquery that filters by the given condition.

    q = From(person) |>
        Where(Fun.">"(Get.year_of_birth, 2000))
    #-> (…) |> Where(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, Lit(2000)))
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 2000)
    =#

Several `Where` operations in a row are collapsed in a single `WHERE` clause.

    q = From(person) |>
        Where(Fun.">"(Get.year_of_birth, 2000)) |>
        Where(Fun."<"(Get.year_of_birth, 2020)) |>
        Where(Fun."<>"(Get.year_of_birth, 2010))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (("person_1"."year_of_birth" > 2000) AND ("person_1"."year_of_birth" < 2020) AND ("person_1"."year_of_birth" <> 2010))
    =#

`Where` that follows `Group` subquery is transformed to a `HAVING` clause.

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Where(Agg.count() .> 10)

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    HAVING (COUNT(*) > 10)
    =#

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Where(Agg.count() .> 10) |>
        Where(Agg.count() .< 100) |>
        Where(Fun.and(Agg.count() .!= 33, Agg.count() .!= 66))

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    HAVING ((COUNT(*) > 10) AND (COUNT(*) < 100) AND (COUNT(*) <> 33) AND (COUNT(*) <> 66))
    =#


## Highlighting

To highlight a node on the output, wrap it with `Highlight`.

    q = From(person) |>
        Highlight(:underline) |>
        Where(Fun.">"(Get.year_of_birth |> Highlight(:bold), 2000) |>
              Highlight(:white)) |>
        Select(Get.person_id) |>
        Highlight(:green)
    #-> (…) |> Highlight(:green)

When the query is displayed on a color terminal, the affected node is
highlighted.

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, Lit(2000))),
        q3 = q2 |> Select(Get.person_id)
        q3
    end
    =#

The `Highlight` node does not otherwise affect processing of the query.

    print(render(q))
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 2000)
    =#

