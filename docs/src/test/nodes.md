# SQL Nodes

    using FunSQL

    using FunSQL:
        Agg, Append, As, Asc, Bind, CrossJoin, Define, Desc, Fun, From, Get,
        Group, Highlight, Iterate, Join, LeftJoin, Limit, Lit, Order, Over,
        Partition, SQLNode, SQLTable, Select, Sort, Var, Where, With,
        WithExternal, ID, render

We start with specifying the database model.

    const concept =
        SQLTable(:concept, columns = [:concept_id, :vocabulary_id, :concept_code, :concept_name])

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
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000)),
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
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000)),
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

    q = From(person) |> Fun.current_date()
    #=>
    ERROR: FunSQL.RebaseError in:
    Fun.current_date()
    =#


## `@funsql`

The `@funsql` macro provides alternative notation for specifying FunSQL queries.

    q = @funsql begin
        from(person)
        filter(year_of_birth > 2000)
        select(person_id)
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000)),
        q3 = q2 |> Select(Get.person_id)
        q3
    end
    =#

We can combine `@funsql` notation with regular Julia code.

    q = @funsql begin
        from(person)
        $(Where(Get.year_of_birth .> 2000))
        select(person_id)
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000)),
        q3 = q2 |> Select(Get.person_id)
        q3
    end
    =#

    q = From(:person) |>
        @funsql(filter(year_of_birth > 2000)) |>
        Select(Get.person_id)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000)),
        q3 = q2 |> Select(Get.person_id)
        q3
    end
    =#

The `@funsql` notation allows us to encapsulate query fragments into query
functions.

    @funsql adults() = from(person).filter(2020 - year_of_birth >= 16)

    display(@funsql adults())
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun.">="(Fun."-"(2020, Get.year_of_birth), 16))
        q2
    end
    =#

Query functions defined with `@funsql` can accept parameters.

    @funsql concept_by_code(v, c) =
        begin
            from(concept)
            filter(vocabulary_id == $v && concept_code == $c)
        end

    display(@funsql concept_by_code("SNOMED", "22298006"))
    #=>
    let q1 = From(:concept),
        q2 = q1 |>
             Where(Fun.and(Fun."="(Get.vocabulary_id, "SNOMED"),
                           Fun."="(Get.concept_code, "22298006")))
        q2
    end
    =#

Query functions support `...` notation.

    @funsql concept_by_code(v, cs...) =
        begin
            from(concept)
            filter(vocabulary_id == $v && in(concept_code, $(cs...)))
        end

    display(@funsql concept_by_code("Visit", "IP", "ER"))
    #=>
    let q1 = From(:concept),
        q2 = q1 |>
             Where(Fun.and(Fun."="(Get.vocabulary_id, "Visit"),
                           Fun.in(Get.concept_code, "IP", "ER")))
        q2
    end
    =#

Query functions support keyword arguments and default values.

    @funsql age(yob = year_of_birth; at = fun(`EXTRACT(YEAR FROM CURRENT_DATE) `)) =
        ($at - $yob)

    q = @funsql begin
        from(person)
        define(
            age => age(),
            age_in_2000 => age(at = 2000))
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |>
             Define(Fun."-"(Fun."EXTRACT(YEAR FROM CURRENT_DATE) "(),
                            Get.year_of_birth) |>
                    As(:age),
                    Fun."-"(2000, Get.year_of_birth) |> As(:age_in_2000))
        q2
    end
    =#

A parameter of a query function accepts a type declaration.

    @funsql concept(c::String, v::String = "SNOMED") =
        concept_by_code($v, $c)

    @funsql concept(id::Int) =
        from(concept).filter(concept_id == $id)

    display(@funsql concept("22298006"))
    #=>
    let q1 = From(:concept),
        q2 = q1 |>
             Where(Fun.and(Fun."="(Get.vocabulary_id, "SNOMED"),
                           Fun."="(Get.concept_code, "22298006")))
        q2
    end
    =#

    display(@funsql concept(4329847))
    #=>
    let q1 = From(:concept),
        q2 = q1 |> Where(Fun."="(Get.concept_id, 4329847))
        q2
    end
    =#

The `@funsql` macro applied to a constant definition transliterates the value.

    @funsql const ip_or_er_visit_q = concept_by_code("Visit", "IP", "ER")

    display(ip_or_er_visit_q)
    #=>
    let q1 = From(:concept),
        q2 = q1 |>
             Where(Fun.and(Fun."="(Get.vocabulary_id, "Visit"),
                           Fun.in(Get.concept_code, "IP", "ER")))
        q2
    end
    =#

A single `@funsql` macro can wrap multiple definitions.

    @funsql begin
        SNOMED(codes...) = concept_by_code("SNOMED", $(codes...))

        const myocardial_infarction_q = SNOMED("22298006")
    end

    display(myocardial_infarction_q)
    #=>
    let q1 = From(:concept),
        q2 = q1 |>
             Where(Fun.and(Fun."="(Get.vocabulary_id, "SNOMED"),
                           Fun."="(Get.concept_code, "22298006")))
        q2
    end
    =#

An ill-formed `@funsql` query triggers an error.

    @funsql for p in person; end
    #=>
    ERROR: LoadError: FunSQL.TransliterationError: ill-formed @funsql notation:
    quote
        for p = person
        end
    end
    in expression starting at …
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

Such plain literals could also be used in `@funsql` notation.

    q = @funsql select(null => missing,
                       boolean => true,
                       integer => 42,
                       text => "SQL is fun!",
                       date => $(Date(2000)))

    display(q)
    #=>
    Select(missing |> As(:null),
           true |> As(:boolean),
           42 |> As(:integer),
           "SQL is fun!" |> As(:text),
           Dates.Date("2000-01-01") |> As(:date))
    =#


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

In the context where a SQL node is expected, a bare symbol is automatically
converted to a reference.

    q = Select(:person_id)

    display(q)
    #-> Select(Get.person_id)

`@funsql` macro translates an identifier to a symbol.  In suitable context,
this symbol will be translated to a column reference.

    @funsql person_id
    #-> :person_id

`@funsql` notation supports hierarchical references.

    @funsql p.person_id
    #-> Get.p.person_id

Use backticks to represent a name that is not a valid identifier.

    @funsql `person_id`
    #-> :person_id

    @funsql `p`.`person_id`
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
    SELECT
      "person_1"."person_id",
      "location_1"."state"
    FROM "person" AS "person_1"
    JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
    =#

When `Get` refers to an unknown attribute, an error is reported.

    q = Select(Get.person_id)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: cannot find `person_id` in:
    Select(Get.person_id)
    =#

    q = From(person) |>
        As(:p) |>
        Select(Get.q.person_id)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: cannot find `q` in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> As(:p) |> Select(Get.q.person_id)
        q2
    end
    =#

An attribute defined in a `Join` shadows any previously defined attributes
with the same name.

    q = person |>
        Join(person, true) |>
        Select(Get.person_id)

    print(render(q))
    #=>
    SELECT "person_2"."person_id"
    FROM "person" AS "person_1"
    CROSS JOIN "person" AS "person_2"
    =#

An incomplete hierarchical reference, as well as an unexpected hierarchical
reference, will result in an error.

    q = person |>
        As(:p) |>
        Select(Get.p)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: incomplete reference `p` in:
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
    ERROR: FunSQL.ReferenceError: unexpected reference after `person_id` in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Select(Get.person_id.year_of_birth)
        q2
    end
    =#

A reference bound to any node other than `Get` will cause an error.

    q = (qₚ = From(person)) |> Select(qₚ.person_id)

    print(render(q))
    #=>
    ERROR: FunSQL.IllFormedError in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Select(q1.person_id)
        q2
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
    SELECT
      "person_1"."person_id",
      "person_1"."gender_concept_id",
      "person_1"."year_of_birth",
      "person_1"."month_of_birth",
      "person_1"."day_of_birth",
      "person_1"."birth_datetime",
      "person_1"."location_id",
      (now() - "person_1"."birth_datetime") AS "age"
    FROM "person" AS "person_1"
    =#

This expression could be referred to by name as if it were a regular table
attribute.

    print(render(q |> Where(Get.age .> "16 years")))
    #=>
    SELECT
      "person_2"."person_id",
      "person_2"."gender_concept_id",
      "person_2"."year_of_birth",
      "person_2"."month_of_birth",
      "person_2"."day_of_birth",
      "person_2"."birth_datetime",
      "person_2"."location_id",
      "person_2"."age"
    FROM (
      SELECT
        "person_1"."person_id",
        "person_1"."gender_concept_id",
        "person_1"."year_of_birth",
        "person_1"."month_of_birth",
        "person_1"."day_of_birth",
        "person_1"."birth_datetime",
        "person_1"."location_id",
        (now() - "person_1"."birth_datetime") AS "age"
      FROM "person" AS "person_1"
    ) AS "person_2"
    WHERE ("person_2"."age" > '16 years')
    =#

A `Define` node can be created using `@funsql` notation.

    q = @funsql from(person).define(age => 2000 - year_of_birth)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Define(Fun."-"(2000, Get.year_of_birth) |> As(:age))
        q2
    end
    =#

`Define` does not create a nested query if the definition is a literal or
a simple reference.

    q = From(person) |>
        Define(:year => Get.year_of_birth,
               :threshold => 2000) |>
        Where(Get.year .>= Get.threshold)

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      "person_1"."gender_concept_id",
      "person_1"."year_of_birth",
      "person_1"."month_of_birth",
      "person_1"."day_of_birth",
      "person_1"."birth_datetime",
      "person_1"."location_id",
      "person_1"."year_of_birth" AS "year",
      2000 AS "threshold"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" >= 2000)
    =#

`Define` can be used to override an existing field.

    q = From(person) |>
        Define(:person_id => Get.year_of_birth, :year_of_birth => Get.person_id)

    print(render(q))
    #=>
    SELECT
      "person_1"."year_of_birth" AS "person_id",
      "person_1"."gender_concept_id",
      "person_1"."person_id" AS "year_of_birth",
      "person_1"."month_of_birth",
      "person_1"."day_of_birth",
      "person_1"."birth_datetime",
      "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

`Define` has no effect if none of the defined fields are used in the query.

    q = From(person) |>
        Define(:age => 2020 .- Get.year_of_birth) |>
        Select(Get.person_id, Get.year_of_birth)

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#

`Define` can be used after `Select`.

    q = From(person) |>
        Select(Get.person_id, Get.year_of_birth) |>
        Define(:age => 2020 .- Get.year_of_birth)

    print(render(q))
    #=>
    SELECT
      "person_2"."person_id",
      "person_2"."year_of_birth",
      (2020 - "person_2"."year_of_birth") AS "age"
    FROM (
      SELECT
        "person_1"."person_id",
        "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    =#

`Define` requires that all definitions have a unique alias.

    From(person) |>
    Define(:age => Fun.now() .- Get.birth_datetime,
           :age => Fun.current_timestamp() .- Get.birth_datetime)
    #=>
    ERROR: FunSQL.DuplicateLabelError: `age` is used more than once in:
    Define(Fun."-"(Fun.now(), Get.birth_datetime) |> As(:age),
           Fun."-"(Fun.current_timestamp(), Get.birth_datetime) |> As(:age))
    =#


## Variables

A query variable is created with the `Var` constructor.

    e = Var(:YEAR)
    #-> Var.YEAR

Alternatively, use shorthand notation.

    Var.YEAR
    #-> Var.YEAR

    Var."YEAR"
    #-> Var.YEAR

    Var[:YEAR]
    #-> Var.YEAR

    Var["YEAR"]
    #-> Var.YEAR

A variable could be created with `@funsql` notation.

    @funsql :YEAR
    #-> Var.YEAR

Unbound query variables are serialized as query parameters.

    q = From(person) |>
        Where(Get.year_of_birth .> Var.YEAR)

    sql = render(q)

    print(sql)
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > :YEAR)
    =#

    sql.vars
    #-> [:YEAR]

Query variables could be bound using the `Bind` constructor.

    q0(person_id) =
        From(visit_occurrence) |>
        Where(Get.person_id .== Var.PERSON_ID) |>
        Bind(:PERSON_ID => person_id)

    q0(1)
    #-> (…) |> Bind(…)

    display(q0(1))
    #=>
    let visit_occurrence = SQLTable(:visit_occurrence, …),
        q1 = From(visit_occurrence),
        q2 = q1 |> Where(Fun."="(Get.person_id, Var.PERSON_ID))
        q2 |> Bind(1 |> As(:PERSON_ID))
    end
    =#

    print(render(q0(1)))
    #=>
    SELECT
      "visit_occurrence_1"."visit_occurrence_id",
      "visit_occurrence_1"."person_id",
      "visit_occurrence_1"."visit_start_date",
      "visit_occurrence_1"."visit_end_date"
    FROM "visit_occurrence" AS "visit_occurrence_1"
    WHERE ("visit_occurrence_1"."person_id" = 1)
    =#

A `Bind` node can be created with `@funsql` notation.

    q = @funsql begin
        from(visit_occurrence)
        filter(person_id == :PERSON_ID)
        bind(:PERSON_ID => person_id)
    end

    display(q)
    #=>
    let q1 = From(:visit_occurrence),
        q2 = q1 |> Where(Fun."="(Get.person_id, Var.PERSON_ID))
        q2 |> Bind(Get.person_id |> As(:PERSON_ID))
    end
    =#

`Bind` lets us create correlated subqueries.

    q = From(person) |>
        Where(Fun.exists(q0(Get.person_id)))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (EXISTS (
      SELECT NULL AS "_"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      WHERE ("visit_occurrence_1"."person_id" = "person_1"."person_id")
    ))
    =#

When an argument to `Bind` is an aggregate, it must be evaluated in a nested
subquery.

    q0(person_id, date) =
        From(observation) |>
        Where(Fun.and(Get.person_id .== Var.PERSON_ID,
                      Get.observation_date .>= Var.DATE)) |>
        Bind(:PERSON_ID => person_id, :DATE => date)

    q = From(visit_occurrence) |>
        Group(Get.person_id) |>
        Where(Fun.exists(q0(Get.person_id, Agg.max(Get.visit_start_date))))

    print(render(q))
    #=>
    SELECT "visit_occurrence_2"."person_id"
    FROM (
      SELECT
        "visit_occurrence_1"."person_id",
        max("visit_occurrence_1"."visit_start_date") AS "max"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_occurrence_2"
    WHERE (EXISTS (
      SELECT NULL AS "_"
      FROM "observation" AS "observation_1"
      WHERE
        ("observation_1"."person_id" = "visit_occurrence_2"."person_id") AND
        ("observation_1"."observation_date" >= "visit_occurrence_2"."max")
    ))
    =#

An empty `Bind` can be created.

    Bind(args = [])
    #-> Bind(args = [])

`Bind` requires that all variables have a unique name.

    Bind(:PERSON_ID => 1, :PERSON_ID => 2)
    #=>
    ERROR: FunSQL.DuplicateLabelError: `PERSON_ID` is used more than once in:
    Bind(1 |> As(:PERSON_ID), 2 |> As(:PERSON_ID))
    =#


## Functions and Operators

A function or an operator invocation is created with the `Fun` constructor.

    Fun.">"
    #-> Fun.:(">")

    e = Fun.">"(Get.year_of_birth, 2000)
    #-> Fun.:(">")(…)

    display(e)
    #-> Fun.">"(Get.year_of_birth, 2000)

Alternatively, `Fun` nodes are created by broadcasting.  Common Julia operators
are replaced with their SQL equivalents.

    #? VERSION >= v"1.7"
    e = Get.location.state .== "IL" .|| Get.location.zip .!= "60615"
    #-> Fun.or(…)

    #? VERSION >= v"1.7"
    display(e)
    #-> Fun.or(Fun."="(Get.location.state, "IL"), Fun."<>"(Get.location.zip, "60615"))

    #? VERSION >= v"1.7"
    e = .!(e .&& Get.year_of_birth .> 1950 .&& Get.year_of_birth .< 1990)
    #-> Fun.not(…)

    #? VERSION >= v"1.7"
    display(e)
    #=>
    Fun.not(Fun.and(Fun.or(Fun."="(Get.location.state, "IL"),
                           Fun."<>"(Get.location.zip, "60615")),
                    Fun.and(Fun.">"(Get.year_of_birth, 1950),
                            Fun."<"(Get.year_of_birth, 1990))))
    =#

A vector of arguments could be passed directly.

    Fun.">"(args = SQLNode[Get.year_of_birth, 2000])
    #-> Fun.:(">")(…)

`Fun` nodes can be generated in `@funsql` notation.

    e = @funsql fun(>, year_of_birth, 2000)

    display(e)
    #-> Fun.">"(Get.year_of_birth, 2000)

In order to generate `Fun` nodes using regular function and operator calls,
we need to declare these functions and operators in advance.

    e = @funsql concat(location.city, ", ", location.state)

    display(e)
    #-> Fun.concat(Get.location.city, ", ", Get.location.state)

    e = @funsql 1950 < year_of_birth < 1990

    display(e)
    #-> Fun.and(Fun."<"(1950, Get.year_of_birth), Fun."<"(Get.year_of_birth, 1990))

    e = @funsql location.state != "IL" || location.zip != 60615

    display(e)
    #-> Fun.or(Fun."<>"(Get.location.state, "IL"), Fun."<>"(Get.location.zip, 60615))

    e = @funsql location.state == "IL" && location.zip == 60615

    display(e)
    #-> Fun.and(Fun."="(Get.location.state, "IL"), Fun."="(Get.location.zip, 60615))

In `@funsql` notation, use backticks to represent a name that is not
a valid identifier.

    e = @funsql fun(`SUBSTRING(? FROM ? FOR ?)`, city, 1, 1)

    display(e)
    #-> Fun."SUBSTRING(? FROM ? FOR ?)"(Get.city, 1, 1)

    q = @funsql `from`(person).`filter`(year_of_birth <= 1964)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun."<="(Get.year_of_birth, 1964))
        q2
    end
    =#

In `@funsql` notation, an `if` statement is converted to a `CASE` expression.

    e = @funsql year_of_birth <= 1964 ? "Boomers" : "Millenials"

    display(e)
    #-> Fun.case(Fun."<="(Get.year_of_birth, 1964), "Boomers", "Millenials")

    e = @funsql year_of_birth <= 1964 ? "Boomers" :
                year_of_birth <= 1980 ? "Generation X" : "Millenials"

    display(e)
    #=>
    Fun.case(Fun."<="(Get.year_of_birth, 1964),
             "Boomers",
             Fun."<="(Get.year_of_birth, 1980),
             "Generation X",
             "Millenials")
    =#

    e = @funsql if year_of_birth <= 1964; "Boomers"; end

    display(e)
    #-> Fun.case(Fun."<="(Get.year_of_birth, 1964), "Boomers")

    e = @funsql begin
        if year_of_birth <= 1964
            "Boomers"
        elseif year_of_birth <= 1980
            "Generation X"
        end
    end

    display(e)
    #=>
    Fun.case(Fun."<="(Get.year_of_birth, 1964),
             "Boomers",
             Fun."<="(Get.year_of_birth, 1980),
             "Generation X")
    =#

    e = @funsql begin
        if year_of_birth <= 1964
            "Boomers"
        elseif year_of_birth <= 1980
            "Generation X"
        elseif year_of_birth <= 1996
            "Millenials"
        else
            "Generation Z"
        end
    end

    display(e)
    #=>
    Fun.case(Fun."<="(Get.year_of_birth, 1964),
             "Boomers",
             Fun."<="(Get.year_of_birth, 1980),
             "Generation X",
             Fun."<="(Get.year_of_birth, 1996),
             "Millenials",
             "Generation Z")
    =#

In a `SELECT` clause, the function name becomes the column alias.

    q = From(location) |>
        Select(Fun.coalesce(Get.city, "N/A"))

    print(render(q))
    #=>
    SELECT coalesce("location_1"."city", 'N/A') AS "coalesce"
    FROM "location" AS "location_1"
    =#

When the name contains only symbol characters, or when it starts or ends
with a space character, it is interpreted as an operator.

    q = From(location) |>
        Select(Fun." || "(Get.city, ", ", Get.state))

    print(render(q))
    #=>
    SELECT ("location_1"."city" || ', ' || "location_1"."state") AS "_"
    FROM "location" AS "location_1"
    =#

The function name containing `?` serves as a template.

    q = From(location) |>
        Select(Fun."SUBSTRING(? FROM ? FOR ?)"(Get.city, 1, 1))

    print(render(q))
    #=>
    SELECT SUBSTRING("location_1"."city" FROM 1 FOR 1) AS "_"
    FROM "location" AS "location_1"
    =#

The number of arguments to a function must coincide with the number of
placeholders in the template.

    Fun."SUBSTRING(? FROM ? FOR ?)"(Get.city)
    #=>
    ERROR: FunSQL.InvalidArityError: `SUBSTRING(? FROM ? FOR ?)` expects 3 arguments, got 1 in:
    Fun."SUBSTRING(? FROM ? FOR ?)"(Get.city)
    =#

Some common functions also validate the number of arguments.

    Fun.case()
    #=>
    ERROR: FunSQL.InvalidArityError: `case` expects at least 2 arguments, got 0 in:
    Fun.case()
    =#

    Fun.is_null(Get.city, Get.state)
    #=>
    ERROR: FunSQL.InvalidArityError: `is_null` expects 1 argument, got 2 in:
    Fun.is_null(Get.city, Get.state)
    =#

    Fun.count(Get.city, Get.state)
    #=>
    ERROR: FunSQL.InvalidArityError: `count` expects from 0 to 1 argument, got 2 in:
    Fun.count(Get.city, Get.state)
    =#

A function invocation may include a nested query.

    p = From(person) |>
        Where(Get.year_of_birth .> 1950)

    q = Select(Fun.exists(p))

    print(render(q))
    #=>
    SELECT (EXISTS (
      SELECT NULL AS "_"
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."gender_concept_id" IN (
      SELECT "concept_1"."concept_id"
      FROM "concept" AS "concept_1"
      WHERE
        ("concept_1"."vocabulary_id" = 'Gender') AND
        ("concept_1"."concept_code" = 'F')
    ))
    =#

FunSQL can simplify logical expressions.

    q = From(person) |>
        Where(Fun.and())

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 1950)
    =#

    q = From(person) |>
        Where(foldl(Fun.and, [Get.year_of_birth .> 1950, Get.year_of_birth .< 1960, Get.year_of_birth .!= 1955], init = Fun.and()))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE
      ("person_1"."year_of_birth" > 1950) AND
      ("person_1"."year_of_birth" < 1960) AND
      ("person_1"."year_of_birth" <> 1955)
    =#

    q = From(person) |>
        Where(Fun.or())

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE FALSE
    =#

    q = From(person) |>
        Where(Fun.or(Get.year_of_birth .> 1950))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 1950)
    =#

    q = From(person) |>
        Where(Fun.or(Fun.or(Fun.or(), Get.year_of_birth .> 1950), Get.year_of_birth .< 1960))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE
      ("person_1"."year_of_birth" > 1950) OR
      ("person_1"."year_of_birth" < 1960)
    =#

    #? VERSION >= v"1.7"
    q = From(person) |>
        Where(Get.year_of_birth .> 1950 .|| Get.year_of_birth .< 1960 .|| Get.year_of_birth .!= 1955)

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE
      ("person_1"."year_of_birth" > 1950) OR
      ("person_1"."year_of_birth" < 1960) OR
      ("person_1"."year_of_birth" <> 1955)
    =#

    q = From(person) |>
        Where(Fun.not(false))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    =#


## `Append`

The `Append` constructor creates a subquery that concatenates the output of
multiple queries.

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
    SELECT
      "union_1"."person_id",
      "union_1"."date"
    FROM (
      SELECT
        "measurement_1"."person_id",
        "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
      UNION ALL
      SELECT
        "observation_1"."person_id",
        "observation_1"."observation_date" AS "date"
      FROM "observation" AS "observation_1"
    ) AS "union_1"
    =#

`Append` can also be specified without the `over` node.

    q = Append(From(measurement) |>
               Define(:date => Get.measurement_date),
               From(observation) |>
               Define(:date => Get.observation_date)) |>
        Select(Get.person_id, Get.date)

    print(render(q))
    #=>
    SELECT
      "union_1"."person_id",
      "union_1"."date"
    FROM (
      SELECT
        "measurement_1"."person_id",
        "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
      UNION ALL
      SELECT
        "observation_1"."person_id",
        "observation_1"."observation_date" AS "date"
      FROM "observation" AS "observation_1"
    ) AS "union_1"
    =#

An `Append` node can be created using `@funsql` notation.

    q = @funsql begin
        from(measurement).define(date => measurement_date)
        append(from(observation).define(date => observation_date))
    end

    display(q)
    #=>
    let q1 = From(:measurement),
        q2 = q1 |> Define(Get.measurement_date |> As(:date)),
        q3 = From(:observation),
        q4 = q3 |> Define(Get.observation_date |> As(:date)),
        q5 = q2 |> Append(q4)
        q5
    end
    =#

`Append` will automatically assign unique aliases to the exported columns.

    q = From(measurement) |>
        Define(:concept_id => Get.measurement_concept_id) |>
        Group(Get.person_id) |>
        Define(:count => 1, :count_2 => 2) |>
        Append(From(observation) |>
               Define(:concept_id => Get.observation_concept_id) |>
               Group(Get.person_id) |>
               Define(:count => 10, :count_2 => 20)) |>
        Select(Get.person_id, :agg_count => Agg.count(), Get.count_2, Get.count)

    print(render(q))
    #=>
    SELECT
      "union_1"."person_id",
      "union_1"."count" AS "agg_count",
      "union_1"."count_2",
      "union_1"."count_3" AS "count"
    FROM (
      SELECT
        "measurement_1"."person_id",
        count(*) AS "count",
        2 AS "count_2",
        1 AS "count_3"
      FROM "measurement" AS "measurement_1"
      GROUP BY "measurement_1"."person_id"
      UNION ALL
      SELECT
        "observation_1"."person_id",
        count(*) AS "count",
        20 AS "count_2",
        10 AS "count_3"
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
    SELECT
      "person_1"."person_id",
      "assessment_1"."date"
    FROM "person" AS "person_1"
    JOIN (
      SELECT
        "measurement_1"."measurement_date" AS "date",
        "measurement_1"."person_id"
      FROM "measurement" AS "measurement_1"
      UNION ALL
      SELECT
        "observation_1"."observation_date" AS "date",
        "observation_1"."person_id"
      FROM "observation" AS "observation_1"
    ) AS "assessment_1" ON ("person_1"."person_id" = "assessment_1"."person_id")
    WHERE ("assessment_1"."date" > CURRENT_TIMESTAMP)
    =#

    q = From(measurement) |>
        Define(:date => Get.measurement_date) |>
        Append(From(observation) |>
        Define(:date => Get.observation_date)) |>
        Group(Get.date) |>
        Define(Agg.count())

    print(render(q))
    #=>
    SELECT
      "union_1"."date",
      count(*) AS "count"
    FROM (
      SELECT "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
      UNION ALL
      SELECT "observation_1"."observation_date" AS "date"
      FROM "observation" AS "observation_1"
    ) AS "union_1"
    GROUP BY "union_1"."date"
    =#

`Append` aligns the columns of its subqueries.

    q = From(measurement) |>
        Select(Get.person_id, :date => Get.measurement_date) |>
        Append(From(observation) |>
               Select(:date => Get.observation_date, Get.person_id))

    print(render(q))
    #=>
    SELECT
      "measurement_1"."person_id",
      "measurement_1"."measurement_date" AS "date"
    FROM "measurement" AS "measurement_1"
    UNION ALL
    SELECT
      "observation_2"."person_id",
      "observation_2"."date"
    FROM (
      SELECT
        "observation_1"."observation_date" AS "date",
        "observation_1"."person_id"
      FROM "observation" AS "observation_1"
    ) AS "observation_2"
    =#

Arguments of `Append` may contain `ORDER BY` or `LIMIT` clauses, which
must be wrapped in a nested subquery.

    q = From(measurement) |>
        Order(Get.measurement_date) |>
        Select(Get.person_id, :date => Get.measurement_date) |>
        Append(From(observation) |>
               Define(:date => Get.observation_date) |>
               Limit(1))

    print(render(q))
    #=>
    SELECT
      "measurement_2"."person_id",
      "measurement_2"."date"
    FROM (
      SELECT
        "measurement_1"."person_id",
        "measurement_1"."measurement_date" AS "date"
      FROM "measurement" AS "measurement_1"
      ORDER BY "measurement_1"."measurement_date"
    ) AS "measurement_2"
    UNION ALL
    SELECT
      "observation_2"."person_id",
      "observation_2"."date"
    FROM (
      SELECT
        "observation_1"."person_id",
        "observation_1"."observation_date" AS "date"
      FROM "observation" AS "observation_1"
      FETCH FIRST 1 ROW ONLY
    ) AS "observation_2"
    =#

An `Append` without any queries can be created explicitly.

    q = Append(args = [])
    #-> Append(args = [])

    print(render(q))
    #=>
    SELECT NULL AS "_"
    WHERE FALSE
    =#

Without an explicit `Select`, the output of `Append` includes the common
columns of the nested queries.

    q = Append(measurement, observation)

    print(render(q))
    #=>
    SELECT "measurement_1"."person_id"
    FROM "measurement" AS "measurement_1"
    UNION ALL
    SELECT "observation_1"."person_id"
    FROM "observation" AS "observation_1"
    =#


## `Iterate`

The `Iterate` constructor creates an iteration query.  In the argument of
`Iterate`, the `From(^)` node refers to the output of the previous iteration.
We could use `Iterate` and `From(^)` to create a factorial table.

    q = Define(:n => 1, :f => 1) |>
        Iterate(From(^) |>
                Define(:n => Get.n .+ 1, :f => Get.f .* (Get.n .+ 1)) |>
                Where(Get.n .<= 10))
    #-> (…) |> Iterate(…)

    display(q)
    #=>
    let q1 = Define(1 |> As(:n), 1 |> As(:f)),
        q2 = From(^),
        q3 = q2 |>
             Define(Fun."+"(Get.n, 1) |> As(:n),
                    Fun."*"(Get.f, Fun."+"(Get.n, 1)) |> As(:f)),
        q4 = q3 |> Where(Fun."<="(Get.n, 10)),
        q5 = q1 |> Iterate(q4)
        q5
    end
    =#

    print(render(q))
    #=>
    WITH RECURSIVE "__1" ("n", "f") AS (
      SELECT
        1 AS "n",
        1 AS "f"
      UNION ALL
      SELECT
        "__3"."n",
        "__3"."f"
      FROM (
        SELECT
          ("__2"."n" + 1) AS "n",
          ("__2"."f" * ("__2"."n" + 1)) AS "f"
        FROM "__1" AS "__2"
      ) AS "__3"
      WHERE ("__3"."n" <= 10)
    )
    SELECT
      "__4"."n",
      "__4"."f"
    FROM "__1" AS "__4"
    =#

An `Iterate` node can be created using `@funsql` notation.

    q = @funsql begin
        define(n => 1, f => 1)
        iterate(define(n => n + 1, f => f * (n + 1)).filter(n <= 10))
    end

    display(q)
    #=>
    let q1 = Define(1 |> As(:n), 1 |> As(:f)),
        q2 = Define(Fun."+"(Get.n, 1) |> As(:n),
                    Fun."*"(Get.f, Fun."+"(Get.n, 1)) |> As(:f)),
        q3 = q2 |> Where(Fun."<="(Get.n, 10)),
        q4 = q1 |> Iterate(q3)
        q4
    end
    =#

The `From(^)` node in front of the iterator query can be omitted.

    q = Define(:n => 1, :f => 1) |>
        Iterate(Define(:n => Get.n .+ 1, :f => Get.f .* (Get.n .+ 1)) |>
                Where(Get.n .<= 10))

    print(render(q))
    #=>
    WITH RECURSIVE "__1" ("n", "f") AS (
      SELECT
        1 AS "n",
        1 AS "f"
      UNION ALL
      SELECT
        "__3"."n",
        "__3"."f"
      FROM (
        SELECT
          ("__2"."n" + 1) AS "n",
          ("__2"."f" * ("__2"."n" + 1)) AS "f"
        FROM "__1" AS "__2"
      ) AS "__3"
      WHERE ("__3"."n" <= 10)
    )
    SELECT
      "__4"."n",
      "__4"."f"
    FROM "__1" AS "__4"
    =#

An `Iterate` node may use a CTE.

    q = Define(:n => 1, :f => 1) |>
        Iterate(Define(:n => Get.n .+ 1, :f => Get.f .* (Get.n .+ 1)) |>
                CrossJoin(From(:threshold)) |>
                Where(Get.n .<= Get.threshold)) |>
        With(:threshold => Define(:threshold => 10))

    print(render(q))
    #=>
    WITH RECURSIVE "threshold_1" ("threshold") AS (
      SELECT 10 AS "threshold"
    ),
    "__1" ("n", "f") AS (
      SELECT
        1 AS "n",
        1 AS "f"
      UNION ALL
      SELECT
        "__3"."n",
        "__3"."f"
      FROM (
        SELECT
          ("__2"."n" + 1) AS "n",
          ("__2"."f" * ("__2"."n" + 1)) AS "f",
          "threshold_2"."threshold"
        FROM "__1" AS "__2"
        CROSS JOIN "threshold_1" AS "threshold_2"
      ) AS "__3"
      WHERE ("__3"."n" <= "__3"."threshold")
    )
    SELECT
      "__4"."n",
      "__4"."f"
    FROM "__1" AS "__4"
    =#

It is an error to use `From(^)` outside of `Iterate`.

    q = From(^)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: self-reference outside of Iterate in:
    let q1 = From(^)
        q1
    end
    =#

The set of columns produced by `Iterate` is the intersection of the columns
produced by the base query and the iterator query.

    q = Define(:k => 0, :m => 0) |>
        Iterate(As(:previous) |>
                Where(Get.previous.m .< 10) |>
                Define(:m => Get.previous.m .+ 1, :n => 0))

    print(render(q))
    #=>
    WITH RECURSIVE "previous_1" ("m") AS (
      SELECT 0 AS "m"
      UNION ALL
      SELECT ("previous_2"."m" + 1) AS "m"
      FROM "previous_1" AS "previous_2"
      WHERE ("previous_2"."m" < 10)
    )
    SELECT "previous_3"."m"
    FROM "previous_1" AS "previous_3"
    =#

`Iterate` aligns the columns of its subqueries.

    q = Select(:n => 1, :f => 1) |>
        Iterate(Where(Get.n .< 10) |>
                Select(:f => (Get.n .+ 1) .* Get.f,
                       :n => Get.n .+ 1))

    print(render(q))
    #=>
    WITH RECURSIVE "__1" ("n", "f") AS (
      SELECT
        1 AS "n",
        1 AS "f"
      UNION ALL
      SELECT
        "__3"."n",
        "__3"."f"
      FROM (
        SELECT
          (("__2"."n" + 1) * "__2"."f") AS "f",
          ("__2"."n" + 1) AS "n"
        FROM "__1" AS "__2"
        WHERE ("__2"."n" < 10)
      ) AS "__3"
    )
    SELECT
      "__4"."n",
      "__4"."f"
    FROM "__1" AS "__4"
    =#


## `As`

An alias to an expression can be added with the `As` constructor.

    e = 42 |> As(:integer)
    #-> (…) |> As(:integer)

    display(e)
    #-> 42 |> As(:integer)

    print(render(Select(e)))
    #=>
    SELECT 42 AS "integer"
    =#

`As` node can be created with `@funsql`.

    e = @funsql (42).as(integer)

    display(e)
    #-> 42 |> As(:integer)

The `=>` shorthand is supported by `@funsql`.

    e = @funsql integer => 42

    display(e)
    #-> :integer => 42

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
    SELECT NULL AS "_"
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
    SELECT
      "person_1"."person_id",
      "person_1"."gender_concept_id",
      "person_1"."year_of_birth",
      "person_1"."month_of_birth",
      "person_1"."day_of_birth",
      "person_1"."birth_datetime",
      "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

`From` adds the schema qualifier when the table has the schema.

    const pg_database =
        SQLTable(qualifiers = [:pg_catalog], :pg_database, columns = [:oid, :datname])

    q = From(pg_database)

    print(render(q))
    #=>
    SELECT
      "pg_database_1"."oid",
      "pg_database_1"."datname"
    FROM "pg_catalog"."pg_database" AS "pg_database_1"
    =#

In a suitable context, a `SQLTable` object is automatically converted to a
`From` subquery.

    print(render(person))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

`From` and other subqueries generate a correct `SELECT` clause when the table
has no columns.

    empty = SQLTable(:empty, columns = Symbol[])

    q = From(empty) |>
        Where(false) |>
        Select(args = [])

    display(q)
    #=>
    let empty = SQLTable(:empty, …),
        q1 = From(empty),
        q2 = q1 |> Where(false),
        q3 = q2 |> Select(args = [])
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT NULL AS "_"
    FROM "empty" AS "empty_1"
    WHERE FALSE
    =#

When `From` takes a Tables-compatible argument, it generates a `VALUES` query.

    using DataFrames

    df = DataFrame(name = ["SQL", "Julia", "FunSQL"],
                   year = [1974, 2012, 2021])

    q = From(df)
    #-> From(…)

    display(q)
    #-> From((name = ["SQL", …], year = [1974, …]))

    print(render(q))
    #=>
    SELECT
      "values_1"."name",
      "values_1"."year"
    FROM (
      VALUES
        ('SQL', 1974),
        ('Julia', 2012),
        ('FunSQL', 2021)
    ) AS "values_1" ("name", "year")
    =#

SQLite does not support column aliases with `AS` clause.

    print(render(q, dialect = :sqlite))
    #=>
    SELECT
      "values_1"."column1" AS "name",
      "values_1"."column2" AS "year"
    FROM (
      VALUES
        ('SQL', 1974),
        ('Julia', 2012),
        ('FunSQL', 2021)
    ) AS "values_1"
    =#

Only columns that are used in the query will be serialized.

    q = From(df) |>
        Select(Get.name)

    print(render(q))
    #=>
    SELECT "values_1"."name"
    FROM (
      VALUES
        ('SQL'),
        ('Julia'),
        ('FunSQL')
    ) AS "values_1" ("name")
    =#

A column of NULLs will be added if no actual columns are used.

    q = From(df) |>
        Group() |>
        Select(Agg.count())

    print(render(q))
    #=>
    SELECT count(*) AS "count"
    FROM (
      VALUES
        (NULL),
        (NULL),
        (NULL)
    ) AS "values_1" ("_")
    =#

Since `VALUES` clause requires at least one row of data, a different
representation is used when the source table is empty.

    q = From(df[1:0, :])

    print(render(q))
    #=>
    SELECT
      NULL AS "name",
      NULL AS "year"
    WHERE FALSE
    =#

The source table must have at least one column.

    q = From(df[1:0, 1:0])
    #=>
    ERROR: DomainError with 0×0 DataFrame:
    a table with at least one column is expected
    =#

`From` can accept a table-valued function.  Since the output type of the
function is not known to FunSQL, you must manually specify the names of
the output columns.

    q = From(Fun.generate_series(0, 100, 10), columns = [:value])
    #-> From(…, columns = [:value])

    display(q)
    #-> From(Fun.generate_series(0, 100, 10), columns = [:value])

    print(render(q))
    #=>
    SELECT "generate_series_1"."value"
    FROM generate_series(0, 100, 10) AS "generate_series_1" ("value")
    =#

`WITH ORDINALITY` annotation adds an extra column that enumerates the output
rows.

    q = From(Fun."? WITH ORDINALITY"(Fun.generate_series(0, 100, 10)),
             columns = [:value, :index])

    print(render(q))
    #=>
    SELECT
      "__1"."value",
      "__1"."index"
    FROM generate_series(0, 100, 10) WITH ORDINALITY AS "__1" ("value", "index")
    =#

A `From` node can be created with `@funsql` notation.

    q = @funsql from(person)

    display(q)
    #-> From(:person)

    q = @funsql from(nothing)

    display(q)
    #-> From(nothing)

    q = @funsql from(^)

    display(q)
    #-> From(^)

    q = @funsql from($person)

    display(q)
    #-> From(SQLTable(:person, …))

    q = @funsql from($df)

    display(q)
    #-> From((name = ["SQL", …], year = [1974, …]))

    funsql_generate_series = FunSQL.FunClosure(:generate_series)

    q = @funsql from(generate_series(0, 100, 10), columns = [value])

    display(q)
    #-> From(Fun.generate_series(0, 100, 10), columns = [:value])

When `From` with a tabular function is attached to the right branch of
a `Join` node, the function may use data from the left branch of `Join`,
even without being wrapped in a `Bind` node.

    q = From(Fun.regexp_split_to_table("(10,20)-(30,40)-(50,60)", "-"),
             columns = [:point]) |>
        CrossJoin(From(Fun.regexp_matches(Get.point, "(\\d+),(\\d+)"),
                       columns = [:captures])) |>
        Select(:x => Fun."CAST(?[1] AS INTEGER)"(Get.captures),
               :y => Fun."CAST(?[2] AS INTEGER)"(Get.captures))

    print(render(q))
    #=>
    SELECT
      CAST("regexp_matches_1"."captures"[1] AS INTEGER) AS "x",
      CAST("regexp_matches_1"."captures"[2] AS INTEGER) AS "y"
    FROM regexp_split_to_table('(10,20)-(30,40)-(50,60)', '-') AS "regexp_split_to_table_1" ("point")
    CROSS JOIN regexp_matches("regexp_split_to_table_1"."point", '(\d+),(\d+)') AS "regexp_matches_1" ("captures")
    =#

All the columns of a tabular function must have distinct names.

    From(Fun."? WITH ORDINALITY"(Fun.generate_series(0, 100, 10)),
         columns = [:index, :index])
    #=>
    ERROR: FunSQL.DuplicateLabelError: `index` is used more than once in:
    let q1 = From(Fun."? WITH ORDINALITY"(Fun.generate_series(0, 100, 10)),
                  columns = [:index, :index])
        q1
    end
    =#

`From(nothing)` will generate a *unit* dataset with one row.

    q = From(nothing)

    display(q)
    #-> From(nothing)

    print(render(q))
    #=>
    SELECT NULL AS "_"
    =#


## `With`, `Over`, and `WithExternal`

We can create a temporary dataset using `With` and refer to it with `From`.

    q = From(:male) |>
        With(From(person) |>
             Where(Get.gender_concept_id .== 8507) |>
             As(:male))

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(:male),
        q2 = From(person),
        q3 = q2 |> Where(Fun."="(Get.gender_concept_id, 8507)),
        q4 = q1 |> With(q3 |> As(:male))
        q4
    end
    =#

    print(render(q))
    #=>
    WITH "male_1" ("person_id", …, "location_id") AS (
      SELECT
        "person_1"."person_id",
        ⋮
        "person_1"."location_id"
      FROM "person" AS "person_1"
      WHERE ("person_1"."gender_concept_id" = 8507)
    )
    SELECT
      "male_2"."person_id",
      ⋮
      "male_2"."location_id"
    FROM "male_1" AS "male_2"
    =#

`With` definitions can be annotated as *materialized* or *not materialized*:

    q = From(:male) |>
        With(From(person) |>
             Where(Get.gender_concept_id .== 8507) |>
             As(:male),
             materialized = true)
    #-> (…) |> With(…, materialized = true)

    print(render(q))
    #=>
    WITH "male_1" ( … ) AS MATERIALIZED (
      ⋮
    )
    SELECT
      ⋮
    FROM "male_1" AS "male_2"
    =#

    q = From(:male) |>
        With(From(person) |>
             Where(Get.gender_concept_id .== 8507) |>
             As(:male),
             materialized = false)

    print(render(q))
    #=>
    WITH "male_1" ( … ) AS NOT MATERIALIZED (
      ⋮
    )
    SELECT
      ⋮
    FROM "male_1" AS "male_2"
    =#

`With` can take more than one definition.

    q = Select(:male_count => From(:male) |> Group() |> Select(Agg.count()),
               :female_count => From(:female) |> Group() |> Select(Agg.count())) |>
        With(:male => From(person) |> Where(Get.gender_concept_id .== 8507),
             :female => From(person) |> Where(Get.gender_concept_id .== 8532))

    print(render(q))
    #=>
    WITH "male_1" ("_") AS (
      SELECT NULL AS "_"
      FROM "person" AS "person_1"
      WHERE ("person_1"."gender_concept_id" = 8507)
    ),
    "female_1" ("_") AS (
      SELECT NULL AS "_"
      FROM "person" AS "person_2"
      WHERE ("person_2"."gender_concept_id" = 8532)
    )
    SELECT
      (
        SELECT count(*) AS "count"
        FROM "male_1" AS "male_2"
      ) AS "male_count",
      (
        SELECT count(*) AS "count"
        FROM "female_1" AS "female_2"
      ) AS "female_count"
    =#

`With` can shadow the previous `With` definition.

    q = From(:cohort) |>
        With(:cohort => From(:cohort) |> Where(Get.gender_concept_id .== 8507)) |>
        With(:cohort => From(:cohort) |> Where(Get.year_of_birth .>= 1950)) |>
        With(:cohort => From(person)) |>
        Select(Get.person_id)

    print(render(q))
    #=>
    WITH "cohort_1" ("person_id", "gender_concept_id", "year_of_birth") AS (
      SELECT
        "person_1"."person_id",
        "person_1"."gender_concept_id",
        "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ),
    "cohort_3" ("person_id", "gender_concept_id") AS (
      SELECT
        "cohort_2"."person_id",
        "cohort_2"."gender_concept_id"
      FROM "cohort_1" AS "cohort_2"
      WHERE ("cohort_2"."year_of_birth" >= 1950)
    ),
    "cohort_5" ("person_id") AS (
      SELECT "cohort_4"."person_id"
      FROM "cohort_3" AS "cohort_4"
      WHERE ("cohort_4"."gender_concept_id" = 8507)
    )
    SELECT "cohort_6"."person_id"
    FROM "cohort_5" AS "cohort_6"
    =#

A `With` node can be created using `@funsql`.

    q = @funsql begin
        from(male)
        with(male => from(person).filter(gender_concept_id == 8507),
             materialized = false)
    end

    display(q)
    #=>
    let q1 = From(:male),
        q2 = From(:person),
        q3 = q2 |> Where(Fun."="(Get.gender_concept_id, 8507)),
        q4 = q1 |> With(q3 |> As(:male), materialized = false)
        q4
    end
    =#

A dataset defined by `With` must have an explicit label assigned to it.

    q = From(:person) |>
        With(From(person))

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: table reference `person` requires As in:
    let person = SQLTable(:person, …),
        q1 = From(:person),
        q2 = From(person),
        q3 = q1 |> With(q2)
        q3
    end
    =#

Datasets defined by `With` must have a unique label.

    From(:p) |>
    With(:p => From(person),
         :p => From(person))
    #=>
    ERROR: FunSQL.DuplicateLabelError: `p` is used more than once in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = From(person),
        q3 = With(q1 |> As(:p), q2 |> As(:p))
        q3
    end
    =#

It is an error for `From` to refer to an undefined dataset.

    q = From(:p)

    print(render(q))
    #=>
    ERROR: FunSQL.ReferenceError: cannot find `p` in:
    let q1 = From(:p)
        q1
    end
    =#

A variant of `With` called `Over` exchanges the positions of the definition
and the query that uses it.

    q = From(person) |>
        Where(Get.gender_concept_id .== 8507) |>
        As(:male) |>
        Over(From(:male))
    #-> (…) |> Over(…)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Where(Fun."="(Get.gender_concept_id, 8507)),
        q3 = From(:male),
        q4 = q2 |> As(:male) |> Over(q3)
        q4
    end
    =#

    print(render(q))
    #=>
    WITH "male_1" ("person_id", …, "location_id") AS (
      SELECT
        "person_1"."person_id",
        ⋮
        "person_1"."location_id"
      FROM "person" AS "person_1"
      WHERE ("person_1"."gender_concept_id" = 8507)
    )
    SELECT
      "male_2"."person_id",
      ⋮
      "male_2"."location_id"
    FROM "male_1" AS "male_2"
    =#

An `Over` node can be created using `@funsql`.

    q = @funsql begin
        male => from(person).filter(gender_concept_id == 8507)
        over(from(male), materialized = true)
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun."="(Get.gender_concept_id, 8507)),
        q3 = From(:male),
        q4 = q2 |> As(:male) |> Over(q3, materialized = true)
        q4
    end
    =#

A variant of `With` called `WithExternal` can be used to prepare a definition
for a `CREATE TABLE AS` or `SELECT INTO` statement.

    with_external_handler((tbl, def)) =
        println("CREATE TEMP TABLE ",
                render(ID(tbl.qualifiers, tbl.name)),
                " (", join([render(ID(c.name)) for (n, c) in tbl.columns], ", "), ") AS\n",
                render(def), ";\n")

    q = From(:male) |>
        WithExternal(From(person) |>
                     Where(Get.gender_concept_id .== 8507) |>
                     As(:male),
                     qualifiers = [:tmp],
                     handler = with_external_handler)
    #-> (…) |> WithExternal(…, qualifiers = [:tmp], handler = with_external_handler)

    print(render(q))
    #=>
    CREATE TEMP TABLE "tmp"."male" ("person_id", …, "location_id") AS
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."gender_concept_id" = 8507);

    SELECT
      "male_1"."person_id",
      ⋮
      "male_1"."location_id"
    FROM "tmp"."male" AS "male_1"
    =#

Datasets defined by `WithExternal` must have a unique label.

    From(:p) |>
    WithExternal(:p => From(person),
                 :p => From(person))
    #=>
    ERROR: FunSQL.DuplicateLabelError: `p` is used more than once in:
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = From(person),
        q3 = WithExternal(q1 |> As(:p), q2 |> As(:p))
        q3
    end
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

A `Group` node can be created using `@funsql` notation.

    q = @funsql from(person).group(year_of_birth)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Group(Get.year_of_birth)
        q2
    end
    =#

Partitions created by `Group` are summarized using aggregate expressions.

    Agg.count
    #-> Agg.count

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Select(Get.year_of_birth, Agg.count())

    print(render(q))
    #=>
    SELECT
      "person_1"."year_of_birth",
      count(*) AS "count"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    =#

Aggregate functions can be created with `@funsql`.

    e = @funsql agg(min, year_of_birth)

    display(e)
    #-> Agg.min(Get.year_of_birth)

    e = @funsql min(year_of_birth)

    display(e)
    #-> Agg.min(Get.year_of_birth)

    e = @funsql count(filter = year_of_birth > 1950)

    display(e)
    #-> Agg.count(filter = Fun.">"(Get.year_of_birth, 1950))

    e = @funsql visit_group.count()

    display(e)
    #-> Get.visit_group |> Agg.count()

    e = @funsql `count`()

    display(e)
    #-> Agg.count()

    e = @funsql visit_group.`count`()

    display(e)
    #-> Get.visit_group |> Agg.count()

    e = @funsql `visit_group`.`count`()

    display(e)
    #-> Get.visit_group |> Agg.count()

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
    SELECT
      "person_1"."person_id",
      "visit_group_1"."count"
    FROM "person" AS "person_1"
    JOIN (
      SELECT
        count(*) AS "count",
        "visit_occurrence_1"."person_id"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_group_1" ON ("person_1"."person_id" = "visit_group_1"."person_id")
    WHERE ("visit_group_1"."count" >= 2)
    =#

`Group` creates a nested subquery when this is necessary to avoid duplicating
the group key expression.

    q = From(person) |>
        Group(:age => 2000 .- Get.year_of_birth)

    print(render(q))
    #=>
    SELECT DISTINCT (2000 - "person_1"."year_of_birth") AS "age"
    FROM "person" AS "person_1"
    =#

    q = From(person) |>
        Group(:age => 2000 .- Get.year_of_birth) |>
        Select(Agg.count())

    print(render(q))
    #=>
    SELECT count(*) AS "count"
    FROM "person" AS "person_1"
    GROUP BY (2000 - "person_1"."year_of_birth")
    =#

    q = From(person) |>
        Group(:age => 2000 .- Get.year_of_birth) |>
        Define(Agg.count())

    print(render(q))
    #=>
    SELECT
      "person_2"."age",
      count(*) AS "count"
    FROM (
      SELECT (2000 - "person_1"."year_of_birth") AS "age"
      FROM "person" AS "person_1"
    ) AS "person_2"
    GROUP BY "person_2"."age"
    =#

`Group` could be used consequently.

    q = From(measurement) |>
        Group(Get.measurement_concept_id) |>
        Group(Agg.count()) |>
        Select(Get.count, :size => Agg.count())

    print(render(q))
    #=>
    SELECT
      "measurement_2"."count",
      count(*) AS "size"
    FROM (
      SELECT count(*) AS "count"
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
    SELECT
      count(*) AS "count",
      min("person_1"."year_of_birth") AS "min",
      max("person_1"."year_of_birth") AS "max"
    FROM "person" AS "person_1"
    =#

`Group` with no keys and no aggregates creates a trivial subquery.

    q = From(person) |>
        Group()

    print(render(q))
    #-> SELECT NULL AS "_"

A `SELECT DISTINCT` query must include all the keys even when they are not used
downstream.

    q = From(person) |>
        Group(Get.year_of_birth) |>
        Group() |>
        Select(Agg.count())

    print(render(q))
    #=>
    SELECT count(*) AS "count"
    FROM (
      SELECT DISTINCT "person_1"."year_of_birth"
      FROM "person" AS "person_1"
    ) AS "person_2"
    =#

`Group` allows specifying the grouping sets, either with grouping mode
indicators `:cube` or `:rollup`, or by explicit enumeration.

    q = From(person) |>
        Group(Get.year_of_birth, sets = :cube)
        Define(Agg.count())

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.year_of_birth, sets = :CUBE)
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    GROUP BY CUBE("person_1"."year_of_birth")
    =#

    q = From(person) |>
        Group(Get.year_of_birth, sets = [[1], Int[]])
        Define(Agg.count())

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.year_of_birth, sets = [[1], []])
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    GROUP BY GROUPING SETS(("person_1"."year_of_birth"), ())
    =#

`Group` allows specifying grouping sets using names of the grouping keys.

    q = From(person) |>
        Group(Get.year_of_birth, Get.gender_concept_id,
              sets = ([:year_of_birth], ["gender_concept_id"]))
        Define(Agg.count())

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |>
             Group(Get.year_of_birth, Get.gender_concept_id, sets = [[1], [2]])
        q2
    end
    =#

`Group` will report when a grouping set refers to an unknown key.

    From(person) |>
    Group(Get.year_of_birth, sets = [[:gender_concept_id], []])
    #=>
    ERROR: FunSQL.InvalidGroupingSetsError: `gender_concept_id` is not a valid key
    =#

`Group` complains about out-of-bound or incomplete grouping sets.

    From(person) |>
    Group(Get.year_of_birth, sets = [[1, 2], [1], []])
    #=>
    ERROR: FunSQL.InvalidGroupingSetsError: `2` is out of bounds in:
    let q1 = Group(Get.year_of_birth, sets = [[1, 2], [1], []])
        q1
    end
    =#

    From(person) |>
    Group(Get.year_of_birth, Get.gender_concept_id,
          sets = [[1], []])
    #=>
    ERROR: FunSQL.InvalidGroupingSetsError: missing keys `[:year_of_birth]` in:
    let q1 = Group(Get.year_of_birth, Get.gender_concept_id, sets = [[1], []])
        q1
    end
    =#

`Group` allows specifying the name of a group field.

    q = From(person) |>
        Group(Get.year_of_birth, name = :person) |>
        Define(Get.person |> Agg.count())

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.year_of_birth, name = :person),
        q3 = q2 |> Define(Get.person |> Agg.count())
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT
      "person_1"."year_of_birth",
      count(*) AS "count"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    =#

`Group` requires all keys to have unique aliases.

    q = From(person) |>
        Group(Get.person_id, Get.person_id)
    #=>
    ERROR: FunSQL.DuplicateLabelError: `person_id` is used more than once in:
    Group(Get.person_id, Get.person_id)
    =#

The name of group field must also be unique.

    q = From(person) |>
        Group(:group => Get.year_of_birth, name = :group)
    #=>
    ERROR: FunSQL.DuplicateLabelError: `group` is used more than once in:
    Group(Get.year_of_birth |> As(:group), name = :group)
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
    SELECT
      "person_1"."person_id",
      "visit_group_1"."max" AS "max_visit_start_date",
      "visit_group_1"."max_2" AS "max_visit_end_date"
    FROM "person" AS "person_1"
    JOIN (
      SELECT
        max("visit_occurrence_1"."visit_start_date") AS "max",
        max("visit_occurrence_1"."visit_end_date") AS "max_2",
        "visit_occurrence_1"."person_id"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_group_1" ON ("person_1"."person_id" = "visit_group_1"."person_id")
    =#

Aggregate expressions can be applied to a filtered portion of a partition.

    e = Agg.count(filter = Get.year_of_birth .> 1950)
    #-> Agg.count(filter = (…))

    display(e)
    #-> Agg.count(filter = Fun.">"(Get.year_of_birth, 1950))

    q = From(person) |> Group() |> Select(e)

    print(render(q))
    #=>
    SELECT (count(*) FILTER (WHERE ("person_1"."year_of_birth" > 1950))) AS "count"
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

`Group` in a `Join` expression shadows any previous applications of `Group`.

    qₚ = From(person)
    qᵥ = From(visit_occurrence) |> Group(:visit_person_id => Get.person_id)
    qₘ = From(measurement) |> Group(:measurement_person_id => Get.person_id)

    q = qₚ |>
        Join(qᵥ, on = Get.person_id .== Get.visit_person_id, left = true) |>
        Join(qₘ, on = Get.person_id .== Get.measurement_person_id, left = true) |>
        Select(Get.person_id, :count => Fun.coalesce(Agg.count(), 0))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      coalesce("measurement_2"."count", 0) AS "count"
    FROM "person" AS "person_1"
    LEFT JOIN (
      SELECT DISTINCT "visit_occurrence_1"."person_id" AS "visit_person_id"
      FROM "visit_occurrence" AS "visit_occurrence_1"
    ) AS "visit_occurrence_2" ON ("person_1"."person_id" = "visit_occurrence_2"."visit_person_id")
    LEFT JOIN (
      SELECT
        count(*) AS "count",
        "measurement_1"."person_id" AS "measurement_person_id"
      FROM "measurement" AS "measurement_1"
      GROUP BY "measurement_1"."person_id"
    ) AS "measurement_2" ON ("person_1"."person_id" = "measurement_2"."measurement_person_id")
    =#

It is still possible to use an aggregate in the context of a Join when the
corresponding `Group` could be determined unambiguously.

    qₚ = From(person)
    qᵥ = From(visit_occurrence) |> Group(:visit_person_id => Get.person_id)

    q = qₚ |>
        Join(qᵥ, on = Get.person_id .== Get.visit_person_id, left = true) |>
        Select(Get.person_id, :count => Fun.coalesce(Agg.count(), 0))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      coalesce("visit_occurrence_2"."count", 0) AS "count"
    FROM "person" AS "person_1"
    LEFT JOIN (
      SELECT
        count(*) AS "count",
        "visit_occurrence_1"."person_id" AS "visit_person_id"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_occurrence_2" ON ("person_1"."person_id" = "visit_occurrence_2"."visit_person_id")
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

A `Partition` node can be created with `@funsql` notation.

    q = @funsql begin
        from(person)
        partition(year_of_birth, order_by = [month_of_birth, day_of_birth])
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |>
             Partition(Get.year_of_birth,
                       order_by = [Get.month_of_birth, Get.day_of_birth])
        q2
    end
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
    SELECT
      "person_1"."person_id",
      (row_number() OVER (PARTITION BY "person_1"."gender_concept_id")) AS "row_number"
    FROM "person" AS "person_1"
    =#

    q = From(visit_occurrence) |>
        Partition(Get.person_id) |>
        Where(Get.visit_start_date .- Agg.min(Get.visit_start_date, filter = Get.visit_start_date .< Get.visit_end_date) .> 30) |>
        Select(Get.person_id, Get.visit_start_date)

    print(render(q))
    #=>
    SELECT
      "visit_occurrence_2"."person_id",
      "visit_occurrence_2"."visit_start_date"
    FROM (
      SELECT
        "visit_occurrence_1"."person_id",
        "visit_occurrence_1"."visit_start_date",
        (min("visit_occurrence_1"."visit_start_date") FILTER (WHERE ("visit_occurrence_1"."visit_start_date" < "visit_occurrence_1"."visit_end_date")) OVER (PARTITION BY "visit_occurrence_1"."person_id")) AS "min"
      FROM "visit_occurrence" AS "visit_occurrence_1"
    ) AS "visit_occurrence_2"
    WHERE (("visit_occurrence_2"."visit_start_date" - "visit_occurrence_2"."min") > 30)
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
    SELECT
      "person_1"."year_of_birth",
      (avg(count(*)) OVER (ORDER BY "person_1"."year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING)) AS "avg"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."year_of_birth"
    =#

A window frame can be specified in `@funsql` notation.

    q = @funsql partition(order_by = [year_of_birth], frame = groups)

    display(q)
    #-> Partition(order_by = [Get.year_of_birth], frame = :GROUPS)

    q = @funsql partition(order_by = [year_of_birth], frame = (mode = range, start = -1, finish = 1))

    display(q)
    #=>
    Partition(order_by = [Get.year_of_birth],
              frame = (mode = :RANGE, start = -1, finish = 1))
    =#

    q = @funsql partition(; order_by = [year_of_birth], frame = (mode = range, start = -Inf, finish = Inf, exclude = current_row))

    display(q)
    #=>
    Partition(
        order_by = [Get.year_of_birth],
        frame =
            (mode = :RANGE, start = -Inf, finish = Inf, exclude = :CURRENT_ROW))
    =#

`Partition` may assign an explicit name to the partition.

    q = From(person) |>
        Group(Get.gender_concept_id) |>
        Partition(name = :all) |>
        Define(:pct => 100 .* Agg.count() ./ (Get.all |> Agg.sum(Agg.count())))

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |> Group(Get.gender_concept_id),
        q3 = q2 |> Partition(name = :all),
        q4 = q3 |>
             Define(Fun."/"(Fun."*"(100, Agg.count()),
                            Get.all |> Agg.sum(Agg.count())) |>
                    As(:pct))
        q4
    end
    =#

    print(render(q))
    #=>
    SELECT
      "person_2"."gender_concept_id",
      ((100 * "person_2"."count") / (sum("person_2"."count") OVER ())) AS "pct"
    FROM (
      SELECT
        "person_1"."gender_concept_id",
        count(*) AS "count"
      FROM "person" AS "person_1"
      GROUP BY "person_1"."gender_concept_id"
    ) AS "person_2"
    =#

This name may shadow an existing column.

    q = From(location) |>
        Partition(Get.location_id, name = :location_id)

    print(render(q))
    #=>
    SELECT
      "location_1"."city",
      "location_1"."state"
    FROM "location" AS "location_1"
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
    SELECT
      "visit_occurrence_3"."person_id",
      min("visit_occurrence_3"."visit_start_date") AS "start_date",
      max("visit_occurrence_3"."visit_end_date") AS "end_date"
    FROM (
      SELECT
        "visit_occurrence_2"."person_id",
        (sum("visit_occurrence_2"."new") OVER (PARTITION BY "visit_occurrence_2"."person_id" ORDER BY "visit_occurrence_2"."visit_start_date", (- "visit_occurrence_2"."new") ROWS UNBOUNDED PRECEDING)) AS "group",
        "visit_occurrence_2"."visit_start_date",
        "visit_occurrence_2"."visit_end_date"
      FROM (
        SELECT
          "visit_occurrence_1"."person_id",
          "visit_occurrence_1"."visit_start_date",
          "visit_occurrence_1"."visit_end_date",
          (CASE WHEN (("visit_occurrence_1"."visit_start_date" - (max("visit_occurrence_1"."visit_end_date") OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date" ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING))) <= 0) THEN 0 ELSE 1 END) AS "new"
        FROM "visit_occurrence" AS "visit_occurrence_1"
      ) AS "visit_occurrence_2"
    ) AS "visit_occurrence_3"
    GROUP BY
      "visit_occurrence_3"."person_id",
      "visit_occurrence_3"."group"
    =#


## `Join`

The `Join` constructor creates a subquery that correlates two nested subqueries.

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
                  Fun."="(Get.location_id, Get.location.location_id),
                  left = true)
        q3
    end
    =#

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
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
                  Fun."="(Get.location_id, Get.location.location_id),
                  left = true)
        q3
    end
    =#

Various `Join` nodes can be created with `@funsql` notation.

    q = @funsql begin
        from(person)
        join(location => from(location),
             on = location_id == location.location_id,
             left = true)
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = From(:location),
        q3 = q1 |>
             Join(q2 |> As(:location),
                  Fun."="(Get.location_id, Get.location.location_id),
                  left = true)
        q3
    end
    =#

    q = @funsql begin
        from(person)
        left_join(location => from(location),
                  location_id == location.location_id)
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = From(:location),
        q3 = q1 |>
             Join(q2 |> As(:location),
                  Fun."="(Get.location_id, Get.location.location_id),
                  left = true)
        q3
    end
    =#

    q = @funsql begin
        from(person)
        cross_join(other => from(person))
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = From(:person),
        q3 = q1 |> Join(q2 |> As(:other), true)
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
    SELECT
      "person_2"."person_id",
      "location_2"."city"
    FROM (
      SELECT
        "person_1"."person_id",
        "person_1"."location_id"
      FROM "person" AS "person_1"
      WHERE ("person_1"."year_of_birth" > 1970)
    ) AS "person_2"
    JOIN (
      SELECT
        "location_1"."city",
        "location_1"."location_id"
      FROM "location" AS "location_1"
      WHERE ("location_1"."state" = 'IL')
    ) AS "location_2" ON ("person_2"."location_id" = "location_2"."location_id")
    =#

`Join` can be applied to correlated subqueries.

    ql(person_id) =
        From(visit_occurrence) |>
        Where(Get.person_id .== Var.PERSON_ID) |>
        Partition(order_by = [Get.visit_start_date]) |>
        Where(Agg.row_number() .== 1) |>
        Bind(:PERSON_ID => person_id)

    print(render(ql(1)))
    #=>
    SELECT
      "visit_occurrence_2"."visit_occurrence_id",
      "visit_occurrence_2"."person_id",
      "visit_occurrence_2"."visit_start_date",
      "visit_occurrence_2"."visit_end_date"
    FROM (
      SELECT
        "visit_occurrence_1"."visit_occurrence_id",
        "visit_occurrence_1"."person_id",
        "visit_occurrence_1"."visit_start_date",
        "visit_occurrence_1"."visit_end_date",
        (row_number() OVER (ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      WHERE ("visit_occurrence_1"."person_id" = 1)
    ) AS "visit_occurrence_2"
    WHERE ("visit_occurrence_2"."row_number" = 1)
    =#

    q = From(person) |>
        Join(:visit => ql(Get.person_id), on = true) |>
        Select(Get.person_id,
               Get.visit.visit_occurrence_id,
               Get.visit.visit_start_date)

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      "visit_1"."visit_occurrence_id",
      "visit_1"."visit_start_date"
    FROM "person" AS "person_1"
    CROSS JOIN LATERAL (
      SELECT
        "visit_occurrence_2"."visit_occurrence_id",
        "visit_occurrence_2"."visit_start_date"
      FROM (
        SELECT
          "visit_occurrence_1"."visit_occurrence_id",
          "visit_occurrence_1"."visit_start_date",
          (row_number() OVER (ORDER BY "visit_occurrence_1"."visit_start_date")) AS "row_number"
        FROM "visit_occurrence" AS "visit_occurrence_1"
        WHERE ("visit_occurrence_1"."person_id" = "person_1"."person_id")
      ) AS "visit_occurrence_2"
      WHERE ("visit_occurrence_2"."row_number" = 1)
    ) AS "visit_1"
    =#

The `LATERAL` keyword is omitted when the join branch is reduced to a function
call.

    q = From(concept) |>
    Join(
        From(Fun.string_to_table(Get.concept_name, " "), columns = [:word]),
        on = true) |>
    Group(Get.word)

    print(render(q))
    #=>
    SELECT DISTINCT "string_to_table_1"."word"
    FROM "concept" AS "concept_1"
    CROSS JOIN string_to_table("concept_1"."concept_name", ' ') AS "string_to_table_1" ("word")
    =#

Some database backends require `LATERAL` even in this case.

    print(render(q, dialect = :spark))
    #=>
    SELECT DISTINCT `string_to_table_1`.`word`
    FROM `concept` AS `concept_1`
    CROSS JOIN LATERAL string_to_table(`concept_1`.`concept_name`, ' ') AS `string_to_table_1` (`word`)
    =#

An optional `Join` is omitted when the output contains no data from
its right branch.

    q = From(person) |>
        LeftJoin(:location => From(location),
                 on = Get.location_id .== Get.location.location_id,
                 optional = true)

    display(q)
    #=>
    let person = SQLTable(:person, …),
        location = SQLTable(:location, …),
        q1 = From(person),
        q2 = From(location),
        q3 = q1 |>
             Join(q2 |> As(:location),
                  Fun."="(Get.location_id, Get.location.location_id),
                  left = true,
                  optional = true)
        q3
    end
    =#

    print(render(q |> Select(Get.year_of_birth)))
    #=>
    SELECT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
    =#

    print(render(q |> Select(Get.year_of_birth, Get.location.state)))
    #=>
    SELECT
      "person_1"."year_of_birth",
      "location_1"."state"
    FROM "person" AS "person_1"
    LEFT JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY "person_1"."year_of_birth"
    =#

An `Order` node can be created with `@funsql` notation.

    q = @funsql begin
        from(person)
        order(year_of_birth)
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Order(Get.year_of_birth)
        q2
    end
    =#

`Order` is often used together with `Limit`.

    q = From(person) |>
        Order(Get.year_of_birth) |>
        Limit(10) |>
        Order(Get.person_id)

    print(render(q))
    #=>
    SELECT
      "person_2"."person_id",
      ⋮
      "person_2"."location_id"
    FROM (
      SELECT
        "person_1"."person_id",
        ⋮
        "person_1"."location_id"
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY
      "person_1"."year_of_birth" DESC NULLS FIRST,
      "person_1"."person_id" ASC
    =#

A generic `Sort` constructor could also be used for this purpose.

    q = From(person) |>
        Order(Get.year_of_birth |> Sort(:desc, nulls = :first),
              Get.person_id |> Sort(:asc))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    ORDER BY
      "person_1"."year_of_birth" DESC NULLS FIRST,
      "person_1"."person_id" ASC
    =#

Sort decorations can be created with `@funsql`.

    q = @funsql begin
        from(person)
        order(year_of_birth.desc(nulls = first), person_id.asc())
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |>
             Order(Get.year_of_birth |> Desc(nulls = :NULLS_FIRST),
                   Get.person_id |> Asc())
        q2
    end
    =#

    q = @funsql begin
        from(person)
        order(year_of_birth.sort(desc, nulls = first), person_id.sort(asc))
    end

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |>
             Order(Get.year_of_birth |> Desc(nulls = :NULLS_FIRST),
                   Get.person_id |> Asc())
        q2
    end
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
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
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
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
    SELECT
      "person_2"."person_id",
      ⋮
      "person_2"."location_id"
    FROM (
      SELECT
        "person_1"."person_id",
        ⋮
        "person_1"."location_id"
      FROM "person" AS "person_1"
      OFFSET 100 ROWS
    ) AS "person_2"
    FETCH FIRST 10 ROWS ONLY
    =#

    q = From(person) |>
        Limit()

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

A `Limit` node can be created with `@funsql` notation.

    q = @funsql from(person).order(person_id).limit(10)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Order(Get.person_id),
        q3 = q2 |> Limit(10)
        q3
    end
    =#

    q = @funsql from(person).order(person_id).limit(100, 10)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Order(Get.person_id),
        q3 = q2 |> Limit(100, 10)
        q3
    end
    =#

    q = @funsql from(person).order(person_id).limit(101:110)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Order(Get.person_id),
        q3 = q2 |> Limit(100, 10)
        q3
    end
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

A `Select` node can be created with `@funsql` notation.

    q = @funsql from(person).select(person_id)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Select(Get.person_id)
        q2
    end
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
    ERROR: FunSQL.DuplicateLabelError: `person_id` is used more than once in:
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
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000))
        q2
    end
    =#

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 2000)
    =#

A `Where` node can be created with `@funsql` notation.

    q = @funsql from(person).filter(year_of_birth > 2000)

    display(q)
    #=>
    let q1 = From(:person),
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000))
        q2
    end
    =#

Several `Where` operations in a row are collapsed to a single `WHERE` clause.

    q = From(person) |>
        Where(Fun.">"(Get.year_of_birth, 2000)) |>
        Where(Fun."<"(Get.year_of_birth, 2020)) |>
        Where(Fun."<>"(Get.year_of_birth, 2010))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE
      ("person_1"."year_of_birth" > 2000) AND
      ("person_1"."year_of_birth" < 2020) AND
      ("person_1"."year_of_birth" <> 2010)
    =#

    q = From(person) |>
        Where(Get.year_of_birth .!= 2010) |>
        Where(Fun.and(Get.year_of_birth .> 2000, Get.year_of_birth .< 2020))

    print(render(q))
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE
      ("person_1"."year_of_birth" <> 2010) AND
      ("person_1"."year_of_birth" > 2000) AND
      ("person_1"."year_of_birth" < 2020)
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
    HAVING (count(*) > 10)
    =#

    q = From(person) |>
        Group(Get.gender_concept_id) |>
        Where(Agg.count(filter = Get.year_of_birth .== 2010) .> 10) |>
        Where(Agg.count(filter = Get.year_of_birth .== 2000) .< 100) |>
        Where(Fun.and(Agg.count(filter = Get.year_of_birth .== 1933) .!= 33,
                      Agg.count(filter = Get.year_of_birth .== 1966) .!= 66))

    print(render(q))
    #=>
    SELECT "person_1"."gender_concept_id"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."gender_concept_id"
    HAVING
      ((count(*) FILTER (WHERE ("person_1"."year_of_birth" = 2010))) > 10) AND
      ((count(*) FILTER (WHERE ("person_1"."year_of_birth" = 2000))) < 100) AND
      ((count(*) FILTER (WHERE ("person_1"."year_of_birth" = 1933))) <> 33) AND
      ((count(*) FILTER (WHERE ("person_1"."year_of_birth" = 1966))) <> 66)
    =#

    q = From(person) |>
        Group(Get.gender_concept_id) |>
        Where(Fun.or(Agg.count(filter = Get.year_of_birth .== 2010) .> 10,
                     Agg.count(filter = Get.year_of_birth .== 2000) .< 100))

    print(render(q))
    #=>
    SELECT "person_1"."gender_concept_id"
    FROM "person" AS "person_1"
    GROUP BY "person_1"."gender_concept_id"
    HAVING
      ((count(*) FILTER (WHERE ("person_1"."year_of_birth" = 2010))) > 10) OR
      ((count(*) FILTER (WHERE ("person_1"."year_of_birth" = 2000))) < 100)
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
        q2 = q1 |> Where(Fun.">"(Get.year_of_birth, 2000)),
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

A `Highlight` node can be created with `@funsql` notation.

    q = @funsql from(person).highlight(red)

    display(q)
    #=>
    let q1 = From(:person)
        q1
    end
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

At the first stage of the translation, `render()` resolves table references
and determines node types.

    #? VERSION >= v"1.7"    # https://github.com/JuliaLang/julia/issues/26798
    withenv("JULIA_DEBUG" => "FunSQL.resolve") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.resolve
    │ let person = SQLTable(:person, …),
    │     location = SQLTable(:location, …),
    │     visit_occurrence = SQLTable(:visit_occurrence, …),
    │     q1 = FromTable(table = person),
    │     q2 = Resolved(RowType(:person_id => ScalarType(),
    │                           :gender_concept_id => ScalarType(),
    │                           :year_of_birth => ScalarType(),
    │                           :month_of_birth => ScalarType(),
    │                           :day_of_birth => ScalarType(),
    │                           :birth_datetime => ScalarType(),
    │                           :location_id => ScalarType()),
    │                   over = q1) |>
    │          Where(Resolved(ScalarType(),
    │                         over = Fun."<="(Resolved(ScalarType(),
    │                                                  over = Get.year_of_birth),
    │                                         Resolved(ScalarType(), over = 2000)))),
    ⋮
    │     WithContext(over = Resolved(RowType(:person_id => ScalarType(),
    │                                         :max_visit_start_date => ScalarType()),
    │                                 over = q9),
    │                 catalog = SQLCatalog(dialect = SQLDialect(), cache = nothing))
    │ end
    └ @ FunSQL …
    =#

Next, `render()` determines, for each tabular node, the data that it must
produce.

    #? VERSION >= v"1.7"
    withenv("JULIA_DEBUG" => "FunSQL.link") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.link
    │ let person = SQLTable(:person, …),
    │     location = SQLTable(:location, …),
    │     visit_occurrence = SQLTable(:visit_occurrence, …),
    │     q1 = FromTable(table = person),
    │     q2 = Get.person_id,
    │     q3 = Get.person_id,
    │     q4 = Get.location_id,
    │     q5 = Get.year_of_birth,
    │     q6 = Linked([q2, q3, q4, q5], 3, over = q1),
    ⋮
    │     WithContext(over = q33,
    │                 catalog = SQLCatalog(dialect = SQLDialect(), cache = nothing))
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
    │ WITH_CONTEXT(
    │     over = ID(:person) |>
    │            AS(:person_1) |>
    │            FROM() |>
    │            WHERE(FUN("<=", ID(:person_1) |> ID(:year_of_birth), LIT(2000))) |>
    │            SELECT(ID(:person_1) |> ID(:person_id),
    │                   ID(:person_1) |> ID(:location_id)) |>
    │            AS(:person_2) |>
    │            FROM() |>
    │            JOIN(ID(:location) |>
    │                 AS(:location_1) |>
    │                 FROM() |>
    │                 WHERE(FUN("=", ID(:location_1) |> ID(:state), LIT("IL"))) |>
    │                 SELECT(ID(:location_1) |> ID(:location_id)) |>
    │                 AS(:location_2),
    │                 FUN("=",
    │                     ID(:person_2) |> ID(:location_id),
    │                     ID(:location_2) |> ID(:location_id))) |>
    │            JOIN(ID(:visit_occurrence) |>
    │                 AS(:visit_occurrence_1) |>
    │                 FROM() |>
    │                 GROUP(ID(:visit_occurrence_1) |> ID(:person_id)) |>
    │                 SELECT(AGG("max",
    │                            ID(:visit_occurrence_1) |> ID(:visit_start_date)) |>
    │                        AS(:max),
    │                        ID(:visit_occurrence_1) |> ID(:person_id)) |>
    │                 AS(:visit_group_1),
    │                 FUN("=",
    │                     ID(:person_2) |> ID(:person_id),
    │                     ID(:visit_group_1) |> ID(:person_id)),
    │                 left = true) |>
    │            SELECT(ID(:person_2) |> ID(:person_id),
    │                   ID(:visit_group_1) |> ID(:max) |> AS(:max_visit_start_date)))
    └ @ FunSQL …
    =#

Finally, the SQL tree is serialized into SQL.

    #? VERSION >= v"1.7"
    withenv("JULIA_DEBUG" => "FunSQL.serialize") do
        render(q)
    end;
    #=>
    ┌ Debug: FunSQL.serialize
    │ SQLString(
    │     """
    │     SELECT
    │       "person_2"."person_id",
    │       "visit_group_1"."max" AS "max_visit_start_date"
    │     FROM (
    │       SELECT
    │         "person_1"."person_id",
    │         "person_1"."location_id"
    │       FROM "person" AS "person_1"
    │       WHERE ("person_1"."year_of_birth" <= 2000)
    │     ) AS "person_2"
    │     JOIN (
    │       SELECT "location_1"."location_id"
    │       FROM "location" AS "location_1"
    │       WHERE ("location_1"."state" = 'IL')
    │     ) AS "location_2" ON ("person_2"."location_id" = "location_2"."location_id")
    │     LEFT JOIN (
    │       SELECT
    │         max("visit_occurrence_1"."visit_start_date") AS "max",
    │         "visit_occurrence_1"."person_id"
    │       FROM "visit_occurrence" AS "visit_occurrence_1"
    │       GROUP BY "visit_occurrence_1"."person_id"
    │     ) AS "visit_group_1" ON ("person_2"."person_id" = "visit_group_1"."person_id")""")
    └ @ FunSQL …
    =#
