# SQL Nodes

    using FunSQL:
        Agg, Append, As, Asc, Bind, Define, Desc, Fun, FunSQL, From, Get,
        Group, Highlight, Join, LeftJoin, Limit, Lit, Order, Partition,
        SQLNode, SQLTable, Select, Sort, Var, Where, render

We start with specifying the database model.


    const concept =
        SQLTable(:concept, columns = [:concept_id, :vocabulary_id, :concept_code])

    const location =
        SQLTable(:location, columns = [:location_id, :city, :state])

    const person =
        SQLTable(:person, columns = [:person_id, :gender_concept_id, :year_of_birth, :month_of_birth, :day_of_birth, :birth_datetime, :location_id])

    const visit_occurrence =
        SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date, :visit_end_date])

    const measurement =
        SQLTable(:measurement, columns = [:measurement_id, :person_id, :measurement_concept_id, :measurement_date])

    const observation =
        SQLTable(:observation, columns = [:observation_id, :person_id, :observation_concept_id, :observation_date])

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

Ill-formed queries are detected.

    q = From(person) |> Agg.count() |> Select(Get.person_id)
    render(q)
    #=>
    ERROR: FunSQL.IllFormedError in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Agg.count() |> Select(Get.person_id)
        q2
    end
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

This is particularly useful when you need to disambiguate the output of `Join`.

    q = From(person) |>
        As(:p) |>
        Join(From(location) |> As(:l),
             on = Get.p.location_id .== Get.l.location_id) |>
        Select(Get.p.person_id, Get.l.state)

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "location_1"."state"
    FROM "person" AS "person_1"
    JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
    =#

Alternatively, node-bound references could be used for this purpose.

    qₚ = From(person)
    qₗ = From(location)
    q = qₚ |>
        Join(qₗ, on = qₚ.location_id .== qₗ.location_id) |>
        Select(qₚ.person_id, qₗ.state)

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "location_1"."state"
    FROM "person" AS "person_1"
    JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
    =#

When `Get` refers to an unknown attribute, an error is reported.

    q = Select(Get.person_id)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: cannot find person_id in:
    Select(Get.person_id)
    =#

    q = From(person) |>
        As(:p) |>
        Select(Get.q.person_id)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: cannot find q in:
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
    ERROR: FunSQL.ReferenceError: person_id is ambiguous in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = From(person),
        q3 = q1 |> Join(q2, Lit(true)),
        q4 = q3 |> Select(Get.person_id)
        q4
    end
    =#

An incomplete hierarchical reference, as well as an unexpected hierarchical
reference, will result in an error.

    q = person |>
        As(:p) |>
        Select(Get.p)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: incomplete reference p in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> As(:p) |> Select(Get.p)
        q2
    end
    =#

    q = person |>
        Select(Get.person_id.year_of_birth)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: unexpected reference after person_id in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Select(Get.person_id.year_of_birth)
        q2
    end
    =#

A node-bound reference that is bound to an unrelated node will cause an error.

    q = (qₚ = From(person)) |>
        Join(:location => From(location) |> Where(qₚ.year_of_birth .>= 1950),
             on = Get.location_id .== Get.location.location_id)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: node-bound reference failed to resolve in:
    let person = SQLTable(:person, …),
        location = SQLTable(:location, …),
        q1 = From(person),
        q2 = From(location),
        q3 = q2 |> Where(Fun.">="(q1.year_of_birth, Lit(1950))),
        q4 = q1 |>
             Join(q3 |> As(:location),
                  Fun."=="(Get.location_id, Get.location.location_id))
        q4
    end
    =#

A node-bound reference which cannot be resolved unambiguously will also cause
an error.

    q = (qₚ = From(person)) |>
        Join(:another => qₚ,
             on = Get.person_id .!= Get.another.person_id) |>
        Select(qₚ.person_id)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: node-bound reference is ambiguous in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |>
             Join(q1 |> As(:another),
                  Fun."!="(Get.person_id, Get.another.person_id)),
        q3 = q2 |> Select(q1.person_id)
        q3
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
    SELECT "person_1"."person_id", …, (NOW() - "person_1"."birth_datetime") AS "age"
    FROM "person" AS "person_1"
    =#

This expression could be referred to by name as if it were a regular table
attribute.

    print(render(q |> Where(Get.age .> "16 years")))
    #=>
    SELECT "person_1"."person_id", …, (NOW() - "person_1"."birth_datetime") AS "age"
    FROM "person" AS "person_1"
    WHERE ((NOW() - "person_1"."birth_datetime") > '16 years')
    =#

`Define` can be used to override an existing field.

    q = From(person) |>
        Define(:person_id => Get.year_of_birth, :year_of_birth => Get.person_id)

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth" AS "person_id", …, "person_1"."person_id" AS "year_of_birth", …
    FROM "person" AS "person_1"
    =#

`Define` has no effect if none of the defined fields are used in the query.

    q = From(person) |>
        Define(:age => 2020 .- Get.year_of_birth) |>
        Select(Get.person_id, Get.year_of_birth)

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#

`Define` can be used after `Select`.

    q = From(person) |>
        Select(Get.person_id, Get.year_of_birth) |>
        Define(:age => 2020 .- Get.year_of_birth)

    print(render(q))
    #=>
    SELECT "person_2"."person_id", "person_2"."year_of_birth", (2020 - "person_2"."year_of_birth") AS "age"
    FROM (
      SELECT "person_1"."person_id", "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    =#

`Define` requires that all definitions have a unique alias.

    From(person) |>
    Define(:age => Fun.now() .- Get.birth_datetime,
           :age => Fun.current_timestamp() .- Get.birth_datetime)
    #=>
    ERROR: FunSQL.DuplicateLabelError: age is used more than once in:
    Define(Fun."-"(Fun.now(), Get.birth_datetime) |> As(:age),
           Fun."-"(Fun.current_timestamp(), Get.birth_datetime) |> As(:age))
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
      SELECT NULL
      FROM "visit_occurrence" AS "visit_occurrence_1"
      WHERE ("visit_occurrence_1"."person_id" = "person_1"."person_id")
    ))
    =#

An empty `Bind` can be created.

    Bind(list = [])
    #-> Bind(list = [])

`Bind` requires that all variables have a unique name.

    Bind(:person_id => 1, :person_id => 2)
    #=>
    ERROR: FunSQL.DuplicateLabelError: person_id is used more than once in:
    Bind(Lit(1) |> As(:person_id), Lit(2) |> As(:person_id))
    =#


## Functions and Operations

A function or an operator invocation is created with the `Fun` constructor.

    Fun.">"
    #-> Fun.:(">")

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
      SELECT NULL
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

FunSQL can properly represents many SQL functions and operators with irregular
syntax.

    q = From(person) |>
        Where(Fun.and(Fun."is null"(Get.birth_datetime), Fun."is not null"(Get.year_of_birth)))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (("person_1"."birth_datetime" IS NULL) AND ("person_1"."year_of_birth" IS NOT NULL))
    =#

FunSQL can simplify logical expressions.

    q = From(person) |>
        Where(Fun.and())

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

    q = From(person) |>
        Select(Get.person_id) |>
        Where(Fun.and())

    print(render(q))
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    =#

    q = From(person) |>
        Where(Fun.and(Get.year_of_birth .> 1950))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 1950)
    =#

    q = From(person) |>
        Where(foldl(Fun.and, [Get.year_of_birth .> 1950, Get.year_of_birth .< 1960, Get.year_of_birth .!= 1955], init = Fun.and()))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (("person_1"."year_of_birth" > 1950) AND ("person_1"."year_of_birth" < 1960) AND ("person_1"."year_of_birth" <> 1955))
    =#

    q = From(person) |>
        Where(Fun.or())

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE FALSE
    =#

    q = From(person) |>
        Where(Fun.or(Get.year_of_birth .> 1950))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 1950)
    =#

    q = From(person) |>
        Where(Fun.or(Fun.or(Fun.or(), Get.year_of_birth .> 1950), Get.year_of_birth .< 1960))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (("person_1"."year_of_birth" > 1950) OR ("person_1"."year_of_birth" < 1960))
    =#

    q = From(person) |>
        Where(Fun."not in"(Get.person_id))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#


## `Append`

The `Append` constructor creates a subquery that merges the output of multiple
queries.

    q = From(measurement) |>
        Define(:date => Get.measurement_date) |>
        Append(From(observation) |>
               Define(:date => Get.observation_date))
    #-> (…) |> Append(…)

    display(q)
    #=>
    let measurement = SQLTable(:measurement, …),
        observation = SQLTable(:observation, …),
        q1 = From(measurement),
        q2 = q1 |> Define(Get.measurement_date |> As(:date)),
        q3 = From(observation),
        q4 = q3 |> Define(Get.observation_date |> As(:date)),
        q5 = q2 |> Append(q4)
        q5
    end
    =#

    print(render(q |> Select(Get.person_id, Get.date)))
    #=>
    SELECT "union_1"."person_id", "union_1"."date"
    FROM (
      SELECT "measurement_1"."person_id", "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
      UNION ALL
      SELECT "observation_1"."person_id", "observation_1"."observation_date" AS "date"
      FROM "observation" AS "observation_1"
    ) AS "union_1"
    =#

`Append` will automatically assign unique aliases to the exported columns.

    q = From(measurement) |>
        Define(:concept_id => Get.measurement_concept_id) |>
        Group(Get.person_id) |>
        Define(:count_2 => 1) |>
        Append(From(observation) |>
               Define(:concept_id => Get.observation_concept_id) |>
               Group(Get.person_id) |>
               Define(:count_2 => 2)) |>
        Select(Get.person_id, Agg.count(), Get.count_2, :count_distinct => Agg.count(distinct = true, Get.concept_id))

    print(render(q))
    #=>
    SELECT "union_1"."person_id", "union_1"."count", "union_1"."count_2", "union_1"."count_3" AS "count_distinct"
    FROM (
      SELECT "measurement_1"."person_id", COUNT(*) AS "count", 1 AS "count_2", COUNT(DISTINCT "measurement_1"."measurement_concept_id") AS "count_3"
      FROM "measurement" AS "measurement_1"
      GROUP BY "measurement_1"."person_id"
      UNION ALL
      SELECT "observation_1"."person_id", COUNT(*) AS "count", 2 AS "count_2", COUNT(DISTINCT "observation_1"."observation_concept_id") AS "count_3"
      FROM "observation" AS "observation_1"
      GROUP BY "observation_1"."person_id"
    ) AS "union_1"
    =#

`Append` will not put duplicate expressions into the `SELECT` clauses of the
nested subqueries.

    q = From(person) |>
        Join(From(measurement) |>
             Define(:date => Get.measurement_date) |>
             Append(From(observation) |>
                    Define(:date => Get.observation_date)) |>
             As(:assessment),
             on = Get.person_id .== Get.assessment.person_id) |>
        Where(Get.assessment.date .> Fun.current_timestamp()) |>
        Select(Get.person_id, Get.assessment.date)

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "assessment_1"."date"
    FROM "person" AS "person_1"
    JOIN (
      SELECT "measurement_1"."person_id", "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
      UNION ALL
      SELECT "observation_1"."person_id", "observation_1"."observation_date" AS "date"
      FROM "observation" AS "observation_1"
    ) AS "assessment_1" ON ("person_1"."person_id" = "assessment_1"."person_id")
    WHERE ("assessment_1"."date" > CURRENT_TIMESTAMP)
    =#

`Append` can also work with queries with an explicit `Select`.

    q = From(measurement) |>
        Select(Get.person_id, :date => Get.measurement_date) |>
        Append(From(observation) |>
               Select(:date => Get.observation_date, Get.person_id))

    print(render(q))
    #=>
    SELECT "measurement_2"."person_id", "measurement_2"."date"
    FROM (
      SELECT "measurement_1"."person_id", "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
    ) AS "measurement_2"
    UNION ALL
    SELECT "observation_2"."person_id", "observation_2"."date"
    FROM (
      SELECT "observation_1"."observation_date" AS "date", "observation_1"."person_id"
      FROM "observation" AS "observation_1"
    ) AS "observation_2"
    =#

An `Append` without any queries can be created explicitly.

    q = Append(list = [])
    #-> Append(list = [])

    print(render(q))
    #-> SELECT NULL

Without an explicit `Select`, the output of `Append` includes the common
columns of the nested queries.

    q = measurement |>
        Append(observation)

    print(render(q))
    #=>
    SELECT "measurement_1"."person_id"
    FROM "measurement" AS "measurement_1"
    UNION ALL
    SELECT "observation_1"."person_id"
    FROM "observation" AS "observation_1"
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
    SELECT NULL
    FROM "person" AS "person_1"
    =#

`As` does not block node-bound references.

    q = (qₚ = From(person)) |>
        As(:p) |>
        Select(qₚ.person_id)

    print(render(q))
    #=>
    SELECT "person_1"."person_id"
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
    SELECT NULL
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

    Agg.count
    #-> Agg.count

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Select(Get.year_of_birth, Agg.count())

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth", COUNT(*) AS "count"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    =#

`Group` will create a single instance of an aggregate function even if it is
used more than once.

    q = From(person) |>
        Join(:visit_group => From(visit_occurrence) |>
                             Group(Get.person_id),
             on = Get.person_id .== Get.visit_group.person_id) |>
        Where(Agg.count(over = Get.visit_group) .>= 2) |>
        Select(Get.person_id, Agg.count(over = Get.visit_group))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "visit_group_1"."count"
    FROM "person" AS "person_1"
    JOIN (
      SELECT "visit_occurrence_1"."person_id", COUNT(*) AS "count"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_group_1" ON ("person_1"."person_id" = "visit_group_1"."person_id")
    WHERE ("visit_group_1"."count" >= 2)
    =#

`Group` could be used consequently.

    q = From(measurement) |>
        Group(Get.measurement_concept_id) |>
        Group(Agg.count()) |>
        Select(Get.count, :size => Agg.count())

    print(render(q))
    #=>
    SELECT "measurement_2"."count", COUNT(*) AS "size"
    FROM (
      SELECT COUNT(*) AS "count"
      FROM "measurement" AS "measurement_1"
      GROUP BY "measurement_1"."measurement_concept_id"
    ) AS "measurement_2"
    GROUP BY "measurement_2"."count"
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
    #-> SELECT NULL

`Group` requires all keys to have unique aliases.

    q = From(person) |>
        Group(Get.person_id, Get.person_id)
    #=>
    ERROR: FunSQL.DuplicateLabelError: person_id is used more than once in:
    Group(Get.person_id, Get.person_id)
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
    SELECT "person_1"."person_id", "visit_group_1"."max" AS "max_visit_start_date", "visit_group_1"."max_2" AS "max_visit_end_date"
    FROM "person" AS "person_1"
    JOIN (
      SELECT "visit_occurrence_1"."person_id", MAX("visit_occurrence_1"."visit_start_date") AS "max", MAX("visit_occurrence_1"."visit_end_date") AS "max_2"
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

It is an error for an aggregate expression to be used without `Group`.

    q = From(person) |> Select(Agg.count())

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: aggregate expression requires Group or Partition in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Select(Agg.count())
        q2
    end
    =#

It is also an error when an aggregate expression cannot determine its `Group`
unambiguously.

    qₚ = From(person)
    qᵥ = From(visit_occurrence) |> Group(Get.person_id)
    qₘ = From(measurement) |> Group(Get.person_id)

    q = qₚ |>
        Join(qᵥ, on = qₚ.person_id .== qᵥ.person_id, left = true) |>
        Join(qₘ, on = qₚ.person_id .== qₘ.person_id, left = true) |>
        Select(qₚ.person_id, :count => Fun.coalesce(Agg.count(), 0))

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: aggregate expression is ambiguous in:
    let person = SQLTable(:person, …),
        visit_occurrence = SQLTable(:visit_occurrence, …),
        measurement = SQLTable(:measurement, …),
        q1 = From(person),
        q2 = From(visit_occurrence),
        q3 = Get.person_id,
        q4 = q2 |> Group(q3),
        q5 = q1 |> Join(q4, Fun."=="(q1.person_id, q4.person_id), left = true),
        q6 = From(measurement),
        q7 = Get.person_id,
        q8 = q6 |> Group(q7),
        q9 = q5 |> Join(q8, Fun."=="(q1.person_id, q8.person_id), left = true),
        q10 = q9 |>
              Select(q1.person_id, Fun.coalesce(Agg.count(), Lit(0)) |> As(:count))
        q10
    end
    =#

It is still possible to use an aggregate in the context of a Join when the
corresponding `Group` could be determined unambiguously.

    qₚ = From(person)
    qᵥ = From(visit_occurrence) |> Group(Get.person_id)

    q = qₚ |>
        Join(qᵥ, on = qₚ.person_id .== qᵥ.person_id, left = true) |>
        Select(qₚ.person_id, :count => Fun.coalesce(Agg.count(), 0))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", COALESCE("visit_occurrence_2"."count", 0) AS "count"
    FROM "person" AS "person_1"
    LEFT JOIN (
      SELECT "visit_occurrence_1"."person_id", COUNT(*) AS "count"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_occurrence_2" ON ("person_1"."person_id" = "visit_occurrence_2"."person_id")
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

It is common to use several `Partition` nodes in a row like in the following
example which calculates non-overlapping visits.

    q = From(visit_occurrence) |>
        Partition(Get.person_id,
                  order_by = [Get.visit_start_date],
                  frame = (mode = :rows, start = -Inf, finish = -1)) |>
        Define(:boundary => Agg.max(Get.visit_end_date)) |>
        Define(:gap => Get.visit_start_date .- Get.boundary) |>
        Define(:new => Fun.case(Get.gap .<= 0, 0, 1)) |>
        Partition(Get.person_id,
                  order_by = [Get.visit_start_date, .- Get.new],
                  frame = :rows) |>
        Define(:group => Agg.sum(Get.new)) |>
        Group(Get.person_id, Get.group) |>
        Define(:start_date => Agg.min(Get.visit_start_date),
               :end_date => Agg.max(Get.visit_end_date)) |>
        Select(Get.person_id, Get.start_date, Get.end_date)

    print(render(q))
    #=>
    SELECT "visit_occurrence_3"."person_id", MIN("visit_occurrence_3"."visit_start_date") AS "start_date", MAX("visit_occurrence_3"."visit_end_date") AS "end_date"
    FROM (
      SELECT "visit_occurrence_2"."person_id", (SUM("visit_occurrence_2"."new") OVER (PARTITION BY "visit_occurrence_2"."person_id" ORDER BY "visit_occurrence_2"."visit_start_date", (- "visit_occurrence_2"."new") ROWS UNBOUNDED PRECEDING)) AS "group", "visit_occurrence_2"."visit_start_date", "visit_occurrence_2"."visit_end_date"
      FROM (
        SELECT "visit_occurrence_1"."person_id", (CASE WHEN (("visit_occurrence_1"."visit_start_date" - (MAX("visit_occurrence_1"."visit_end_date") OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date" ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING))) <= 0) THEN 0 ELSE 1 END) AS "new", "visit_occurrence_1"."visit_start_date", "visit_occurrence_1"."visit_end_date"
        FROM "visit_occurrence" AS "visit_occurrence_1"
      ) AS "visit_occurrence_2"
    ) AS "visit_occurrence_3"
    GROUP BY "visit_occurrence_3"."person_id", "visit_occurrence_3"."group"
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
    SELECT "person_2"."person_id", "location_2"."city"
    FROM (
      SELECT "person_1"."location_id", "person_1"."person_id"
      FROM "person" AS "person_1"
      WHERE ("person_1"."year_of_birth" > 1970)
    ) AS "person_2"
    JOIN (
      SELECT "location_1"."location_id", "location_1"."city"
      FROM "location" AS "location_1"
      WHERE ("location_1"."state" = 'IL')
    ) AS "location_2" ON ("person_2"."location_id" = "location_2"."location_id")
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
    SELECT "visit_occurrence_2"."visit_occurrence_id", "visit_occurrence_2"."person_id", "visit_occurrence_2"."visit_start_date", "visit_occurrence_2"."visit_end_date"
    FROM (
      SELECT "visit_occurrence_1"."visit_occurrence_id", "visit_occurrence_1"."person_id", "visit_occurrence_1"."visit_start_date", "visit_occurrence_1"."visit_end_date", (ROW_NUMBER() OVER (ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      WHERE ("visit_occurrence_1"."person_id" = 1)
    ) AS "visit_occurrence_2"
    WHERE ("visit_occurrence_2"."row_number" = 1)
    =#

    q = From(person) |>
        Join(:visit => q0(Get.person_id), on = true) |>
        Select(Get.person_id,
               Get.visit.visit_occurrence_id,
               Get.visit.visit_start_date)

    print(render(q))
    #=>
    SELECT "person_1"."person_id", "visit_1"."visit_occurrence_id", "visit_1"."visit_start_date"
    FROM "person" AS "person_1"
    CROSS JOIN LATERAL (
      SELECT "visit_occurrence_2"."visit_occurrence_id", "visit_occurrence_2"."visit_start_date"
      FROM (
        SELECT "visit_occurrence_1"."visit_occurrence_id", "visit_occurrence_1"."visit_start_date", (ROW_NUMBER() OVER (ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number"
        FROM "visit_occurrence" AS "visit_occurrence_1"
        WHERE ("visit_occurrence_1"."person_id" = "person_1"."person_id")
      ) AS "visit_occurrence_2"
      WHERE ("visit_occurrence_2"."row_number" = 1)
    ) AS "visit_1"
    =#


## `Order`

The `Order` constructor creates a subquery for sorting the data.

    q = From(person) |>
        Order(Get.year_of_birth)
    #-> (…) |> Order(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Order(Get.year_of_birth)
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."year_of_birth"
    =#

`Order` is often used together with `Limit`.

    q = From(person) |>
        Order(Get.year_of_birth) |>
        Limit(10) |>
        Order(Get.person_id)

    print(render(q))
    #=>
    SELECT "person_2"."person_id", …, "person_2"."location_id"
    FROM (
      SELECT "person_1"."person_id", …, "person_1"."location_id"
      FROM "person" AS "person_1"
      ORDER BY "person_1"."year_of_birth"
      FETCH FIRST 10 ROWS ONLY
    ) AS "person_2"
    ORDER BY "person_2"."person_id"
    =#

An `Order` without columns to sort by is a no-op.

    q = From(person) |>
        Order(by = [])
    #-> (…) |> Order(by = [])

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

It is possible to specify ascending or descending order of the sort
column.

    q = From(person) |>
        Order(Get.year_of_birth |> Desc(nulls = :first),
              Get.person_id |> Asc())

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |>
             Order(Get.year_of_birth |> Desc(nulls = :NULLS_FIRST),
                   Get.person_id |> Asc())
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."year_of_birth" DESC NULLS FIRST, "person_1"."person_id" ASC
    =#

A generic `Sort` constructor could also be used for this purpose.

    q = From(person) |>
        Order(Get.year_of_birth |> Sort(:desc, nulls = :first),
              Get.person_id |> Sort(:asc))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."year_of_birth" DESC NULLS FIRST, "person_1"."person_id" ASC
    =#


## `Limit`

The `Limit` constructor creates a subquery that takes a fixed-size slice of the
dataset.

    q = From(person) |>
        Order(Get.person_id) |>
        Limit(10)
    #-> (…) |> Limit(10)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Order(Get.person_id),
        q3 = q2 |> Limit(10)
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."person_id"
    FETCH FIRST 10 ROWS ONLY
    =#

Both the offset and the limit can be specified.

    q = From(person) |>
        Order(Get.person_id) |>
        Limit(100, 10)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Order(Get.person_id),
        q3 = q2 |> Limit(100, 10)
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."person_id"
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

    q = From(person) |>
        Order(Get.person_id) |>
        Limit(101:110)

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."person_id"
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

    q = From(person) |>
        Limit(offset = 100) |>
        Limit(limit = 10)

    print(render(q))
    #=>
    SELECT "person_2"."person_id", …, "person_2"."location_id"
    FROM (
      SELECT "person_1"."person_id", …, "person_1"."location_id"
      FROM "person" AS "person_1"
      OFFSET 100 ROWS
    ) AS "person_2"
    FETCH FIRST 10 ROWS ONLY
    =#

    q = From(person)
        Limit()

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
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

`Select` does not have to be the last subquery in a chain, but it always
creates a complete subquery.

    q = From(person) |>
        Select(Get.year_of_birth) |>
        Where(Fun.">"(Get.year_of_birth, 2000))

    print(render(q))
    #=>
    SELECT "person_2"."year_of_birth"
    FROM (
      SELECT "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    WHERE ("person_2"."year_of_birth" > 2000)
    =#

`Select` requires all columns in the list to have unique aliases.

    q = From(person) |>
        Select(Get.person_id, Get.person_id)
    #=>
    ERROR: FunSQL.DuplicateLabelError: person_id is used more than once in:
    Select(Get.person_id, Get.person_id)
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

    q = From(person) |>
        Where(Get.year_of_birth .!= 2010) |>
        Where(Fun.and(Get.year_of_birth .> 2000, Get.year_of_birth .< 2020))

    print(render(q))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (("person_1"."year_of_birth" <> 2010) AND ("person_1"."year_of_birth" > 2000) AND ("person_1"."year_of_birth" < 2020))
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


## Debugging

Enable debug logging to get some insight on how FunSQL translates a query
object into SQL.  Set the `JULIA_DEBUG` environment variable to the name of
a translation stage and `render()` will print the result of this stage.

Consider the following query.

    q = From(person) |>
        Where(Get.year_of_birth .<= 2000) |>
        Join(:location => From(location) |>
                          Where(Get.state .== "IL"),
             on = (Get.location_id .== Get.location.location_id)) |>
        Join(:visit_group => From(visit_occurrence) |>
                             Group(Get.person_id),
             on = (Get.person_id .== Get.visit_group.person_id),
             left = true) |>
        Select(Get.person_id,
               :max_visit_start_date =>
                   Get.visit_group |> Agg.max(Get.visit_start_date))

At the first stage of the translation, `render()` augments the query object
with some additional nodes.  A `Box` node is inserted in front of each
tabular node and hierarchical `Get` nodes are reversed.

    #? VERSION >= v"1.7"    # https://github.com/JuliaLang/julia/issues/26798
    withenv("JULIA_DEBUG" => "FunSQL.annotate") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.annotate
    │ let person = SQLTable(:person, …),
    │     location = SQLTable(:location, …),
    │     visit_occurrence = SQLTable(:visit_occurrence, …),
    │     q1 = From(person),
    │     q2 = q1 |> Box(),
    ⋮
    │     q19 = q18 |>
    │           Select(Get.person_id,
    │                  NameBound(over = Agg.max(Get.visit_start_date),
    │                            name = :visit_group) |>
    │                  As(:max_visit_start_date)),
    │     q20 = q19 |> Box()
    │     q20
    │ end
    └ @ FunSQL …
    =#

Next, `render()` determines the type of each tabular node and attaches
it to the corresponding `Box` node.

    #? VERSION >= v"1.7"
    withenv("JULIA_DEBUG" => "FunSQL.resolve!") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.resolve!
    │ let person = SQLTable(:person, …),
    │     location = SQLTable(:location, …),
    │     visit_occurrence = SQLTable(:visit_occurrence, …),
    │     q1 = From(person),
    │     q2 = q1 |>
    │          Box(type = BoxType(:person,
    │                             :person_id => ScalarType(),
    │                             :gender_concept_id => ScalarType(),
    │                             :year_of_birth => ScalarType(),
    │                             :month_of_birth => ScalarType(),
    │                             :day_of_birth => ScalarType(),
    │                             :birth_datetime => ScalarType(),
    │                             :location_id => ScalarType())),
    ⋮
    │     q19 = q18 |>
    │           Select(Get.person_id,
    │                  NameBound(over = Agg.max(Get.visit_start_date),
    │                            name = :visit_group) |>
    │                  As(:max_visit_start_date)),
    │     q20 = q19 |>
    │           Box(type = BoxType(:person,
    │                              :person_id => ScalarType(),
    │                              :max_visit_start_date => ScalarType()))
    │     q20
    │ end
    └ @ FunSQL …
    =#

Next, `render()` validates column references and aggregate functions
and determine the columns to be provided by each tabular query.

    #? VERSION >= v"1.7"
    withenv("JULIA_DEBUG" => "FunSQL.link!") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.link!
    │ let person = SQLTable(:person, …),
    │     location = SQLTable(:location, …),
    │     visit_occurrence = SQLTable(:visit_occurrence, …),
    │     q1 = From(person),
    │     q2 = Get.location_id,
    │     q3 = Get.person_id,
    │     q4 = Get.person_id,
    │     q5 = Get.year_of_birth,
    │     q6 = q1 |>
    │          Box(type = BoxType(:person,
    │                             :person_id => ScalarType(),
    │                             :gender_concept_id => ScalarType(),
    │                             :year_of_birth => ScalarType(),
    │                             :month_of_birth => ScalarType(),
    │                             :day_of_birth => ScalarType(),
    │                             :birth_datetime => ScalarType(),
    │                             :location_id => ScalarType()),
    │              refs = [q2, q3, q4, q5]),
    ⋮
    │     q32 = q31 |> Select(q4, q28 |> As(:max_visit_start_date)),
    │     q33 = q32 |>
    │           Box(type = BoxType(:person,
    │                              :person_id => ScalarType(),
    │                              :max_visit_start_date => ScalarType()),
    │               refs = [Get.person_id, Get.max_visit_start_date])
    │     q33
    │ end
    └ @ FunSQL …
    =#

On the next stage, the query object is converted to a SQL syntax tree.

    #? VERSION >= v"1.7"
    withenv("JULIA_DEBUG" => "FunSQL.translate") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.translate
    │ ID(:person) |>
    │ AS(:person_1) |>
    │ FROM() |>
    │ WHERE(OP("<=", ID(:person_1) |> ID(:year_of_birth), LIT(2000))) |>
    │ SELECT(ID(:person_1) |> ID(:location_id), ID(:person_1) |> ID(:person_id)) |>
    │ AS(:person_2) |>
    │ FROM() |>
    │ JOIN(ID(:location) |>
    │      AS(:location_1) |>
    │      FROM() |>
    │      WHERE(OP("=", ID(:location_1) |> ID(:state), LIT("IL"))) |>
    │      SELECT(ID(:location_1) |> ID(:location_id)) |>
    │      AS(:location_2),
    │      OP("=",
    │         ID(:person_2) |> ID(:location_id),
    │         ID(:location_2) |> ID(:location_id))) |>
    │ JOIN(ID(:visit_occurrence) |>
    │      AS(:visit_occurrence_1) |>
    │      FROM() |>
    │      GROUP(ID(:visit_occurrence_1) |> ID(:person_id)) |>
    │      SELECT(ID(:visit_occurrence_1) |> ID(:person_id),
    │             AGG("MAX", ID(:visit_occurrence_1) |> ID(:visit_start_date)) |>
    │             AS(:max)) |>
    │      AS(:visit_group_1),
    │      OP("=",
    │         ID(:person_2) |> ID(:person_id),
    │         ID(:visit_group_1) |> ID(:person_id)),
    │      left = true) |>
    │ SELECT(ID(:person_2) |> ID(:person_id),
    │        ID(:visit_group_1) |> ID(:max) |> AS(:max_visit_start_date))
    └ @ FunSQL …
    =#

Finally, the SQL tree is serialized into SQL.

    #? VERSION >= v"1.7"
    withenv("JULIA_DEBUG" => "FunSQL.render") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.render
    │ SELECT "person_2"."person_id", "visit_group_1"."max" AS "max_visit_start_date"
    │ FROM (
    │   SELECT "person_1"."location_id", "person_1"."person_id"
    │   FROM "person" AS "person_1"
    │   WHERE ("person_1"."year_of_birth" <= 2000)
    │ ) AS "person_2"
    │ JOIN (
    │   SELECT "location_1"."location_id"
    │   FROM "location" AS "location_1"
    │   WHERE ("location_1"."state" = 'IL')
    │ ) AS "location_2" ON ("person_2"."location_id" = "location_2"."location_id")
    │ LEFT JOIN (
    │   SELECT "visit_occurrence_1"."person_id", MAX("visit_occurrence_1"."visit_start_date") AS "max"
    │   FROM "visit_occurrence" AS "visit_occurrence_1"
    │   GROUP BY "visit_occurrence_1"."person_id"
    │ ) AS "visit_group_1" ON ("person_2"."person_id" = "visit_group_1"."person_id")
    └ @ FunSQL …
    =#

