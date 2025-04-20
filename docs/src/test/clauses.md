# SQL Clauses

    using FunSQL:
        AGG, AS, ASC, DESC, FROM, FUN, GROUP, HAVING, ID, JOIN, LIMIT, LIT,
        NOTE, ORDER, PARTITION, SELECT, SORT, UNION, VALUES, VAR, WHERE,
        WINDOW, WITH, SQLTable, pack, render

The syntactic structure of a SQL query is represented as a tree of `SQLSyntax`
objects.  Different types of syntax nodes are created by specialized constructors
and connected using the chain (`|>`) operator.

    s = FROM(:person) |>
        SELECT(:person_id, :year_of_birth)
    #-> (…) |> SELECT(…)

Displaying a `SQLSyntax` object shows how it was constructed.

    display(s)
    #-> ID(:person) |> FROM() |> SELECT(ID(:person_id), ID(:year_of_birth))

A `SQLSyntax` object is a linked list consisting of a concrete `head` clause
and an optional `tail`.

    display(s.head)
    #-> SELECT(ID(:person_id), ID(:year_of_birth)).head

    display(s.tail)
    #-> ID(:person) |> FROM()

To generate SQL, we use function `render()`.

    print(render(s))
    #=>
    SELECT
      "person_id",
      "year_of_birth"
    FROM "person"
    =#


## SQL Literals

A SQL literal is created using a `LIT()` constructor.

    s = LIT("SQL is fun!")
    #-> LIT("SQL is fun!")

Values of certain Julia data types are automatically converted to SQL
literals when they are used as arguments of clause constructors.

    using Dates

    s = SELECT(missing, true, 42, "SQL is fun!", Date(2000))

    display(s)
    #=>
    SELECT(LIT(missing),
           LIT(true),
           LIT(42),
           LIT("SQL is fun!"),
           LIT(Dates.Date("2000-01-01")))
    =#

    print(render(s))
    #=>
    SELECT
      NULL,
      TRUE,
      42,
      'SQL is fun!',
      '2000-01-01'
    =#

Some values may render differently depending on the dialect.

    s = LIT(false)

    print(render(s, dialect = :sqlserver))
    #-> (1 = 0)

A quote character in a string literal is represented by a pair of quotes.

    s = LIT("O'Hare")

    print(render(s))
    #-> 'O''Hare'

Some dialects use backslash to escape quote characters.

    print(render(s, dialect = :spark))
    #-> 'O\'Hare'


## SQL Identifiers

A SQL identifier is created with `ID()` constructor.

    s = ID(:person)
    #-> ID(:person)

    display(s)
    #-> ID(:person)

    print(render(s))
    #-> "person"

Serialization of an identifier depends on the SQL dialect.

    print(render(s, dialect = :sqlserver))
    #-> [person]

A quote character in an identifier is properly escaped.

    s = ID("year of \"birth\"")

    print(render(s))
    #-> "year of ""birth"""

A qualified identifier is created using the chain operator.

    s = ID(:person) |> ID(:year_of_birth)
    #-> (…) |> ID(:year_of_birth)

    display(s)
    #-> ID(:person) |> ID(:year_of_birth)

    print(render(s))
    #-> "person"."year_of_birth"

There are several shorthands for creating qualified identifiers.

    display(ID(:public, :person))
    #-> ID(:public) |> ID(:person)

    display(ID(:public, :person, :year_of_birth))
    #-> ID(:public) |> ID(:person) |> ID(:year_of_birth)

    display(ID([:public, :person], :year_of_birth))
    #-> ID(:public) |> ID(:person) |> ID(:year_of_birth)

    t = SQLTable(qualifiers = [:public], :person, :person_id, :year_of_birth)

    display(ID(t))
    #-> ID(:public) |> ID(:person)

    display(FROM(t))
    #-> ID(:public) |> ID(:person) |> FROM()

Symbols and pairs of symbols are automatically converted to SQL identifiers
when they are used as arguments of clause constructors.

    s = FROM(:p => :person) |> SELECT((:p, :person_id))
    display(s)
    #-> ID(:person) |> AS(:p) |> FROM() |> SELECT(ID(:p) |> ID(:person_id))

    print(render(s))
    #=>
    SELECT "p"."person_id"
    FROM "person" AS "p"
    =#


## SQL Variables

Placeholder parameters to a SQL query are created with `VAR()` constructor.

    s = VAR(:YEAR)
    #-> VAR(:YEAR)

    display(s)
    #-> VAR(:YEAR)

    print(render(s))
    #-> :YEAR

Rendering of a SQL parameter depends on the chosen dialect.

    print(render(s, dialect = :sqlite))
    #-> ?1

    print(render(s, dialect = :postgresql))
    #-> $1

    print(render(s, dialect = :mysql))
    #-> ?

Function `pack()` converts named parameters to a positional form.

    s = FROM(:person) |>
        WHERE(FUN(:or, FUN("=", :gender_concept_id, VAR(:GENDER)),
                       FUN("=", :gender_source_concept_id, VAR(:GENDER)))) |>
        SELECT(:person_id)

    sql = render(s, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE
      ("gender_concept_id" = ?1) OR
      ("gender_source_concept_id" = ?1)
    =#

    pack(sql, (GENDER = 8532,))
    #-> Any[8532]

    pack(sql, Dict(:GENDER => 8532))
    #-> Any[8532]

    pack(sql, Dict("GENDER" => 8532))
    #-> Any[8532]

If the dialect does not support numbered parameters, `pack()` may need to
duplicate parameter values.

    sql = render(s, dialect = :mysql)

    print(sql)
    #=>
    SELECT `person_id`
    FROM `person`
    WHERE
      (`gender_concept_id` = ?) OR
      (`gender_source_concept_id` = ?)
    =#

    pack(sql, (GENDER = 8532,))
    #-> Any[8532, 8532]


## SQL Functions and Operators

An application of a SQL function is created with `FUN()` constructor.

    s = FUN(:concat, :city, ", ", :state)
    #-> FUN("concat", …)

    display(s)
    #-> FUN("concat", ID(:city), LIT(", "), ID(:state))

    print(render(s))
    #-> concat("city", ', ', "state")

    s = FUN(:now)
    #-> FUN("now")

    print(render(s))
    #-> now()

`FUN()` with an empty name generates a comma-separated list of values.

    s = FUN("", "60614", "60615")

    print(render(s))
    #-> ('60614', '60615')

A name that contains only symbol characters is considered an operator.

    s = FUN("||", :city, ", ", :state)

    print(render(s))
    #-> ("city" || ', ' || "state")

To create an operator containing alphabetical characters, add a leading or a
trailing space to its name.

    s = FUN(" IS DISTINCT FROM ", :zip, missing)

    print(render(s))
    #-> ("zip" IS DISTINCT FROM NULL)

    s = FUN(" IS DISTINCT FROM", :zip, missing)

    print(render(s))
    #-> ("zip" IS DISTINCT FROM NULL)

    s = FUN(" COLLATE \"C\"", :zip)

    print(render(s))
    #-> ("zip" COLLATE "C")

    s = FUN("DATE ", "2000-01-01")

    print(render(s))
    #-> (DATE '2000-01-01')

    s = FUN("CURRENT_TIME ")

    print(render(s))
    #-> CURRENT_TIME

    s = FUN(" CURRENT_TIME")

    print(render(s))
    #-> CURRENT_TIME

To create a SQL expression with irregular syntax, supply `FUN()` with a
*template* string.

    s = FUN("SUBSTRING(? FROM ? FOR ?)", :zip, 1, 3)

    print(render(s))
    #-> SUBSTRING("zip" FROM 1 FOR 3)

    s = FUN("?::date", "2000-01-01")

    print(render(s))
    #-> '2000-01-01'::date

Write `??` to  use `?` in an operator name or a template.

    s = FUN("??-", "(1,0)", "(0,0)")

    print(render(s))
    #-> ('(1,0)' ?- '(0,0)')

    s = FUN("('(?,?)'::point ??| '(?,?)'::point)", 0, 1, 0, 0)

    print(render(s))
    #-> ('(0,1)'::point ?| '(0,0)'::point)

Some functions and operators have specialized serializers.

    s = FUN(:and)

    print(render(s))
    #-> TRUE

    s = FUN(:and, true)

    print(render(s))
    #-> TRUE

    s = FUN(:and, true, false)

    print(render(s))
    #-> (TRUE AND FALSE)

    s = FUN(:or)

    print(render(s))
    #-> FALSE

    s = FUN(:or, true)

    print(render(s))
    #-> TRUE

    s = FUN(:or, true, false)

    print(render(s))
    #-> (TRUE OR FALSE)

    s = FUN(:not, true)

    print(render(s))
    #-> (NOT TRUE)

    s = FUN(:concat, :city, ", ", :state)

    print(render(s))
    #-> concat("city", ', ', "state")

    print(render(s, dialect = :sqlite))
    #-> ("city" || ', ' || "state")

    s = FUN(:in, :zip)

    print(render(s))
    #-> FALSE

    s = FUN(:in, :zip, "60614", "60615")

    print(render(s))
    #-> ("zip" IN ('60614', '60615'))

    s = SELECT(FUN(:in, "60615", FROM(:location) |> SELECT(:zip)))

    print(render(s))
    #=>
    SELECT ('60615' IN (
      SELECT "zip"
      FROM "location"
    ))
    =#

    s = FUN(:not_in, :zip)

    print(render(s))
    #-> TRUE

    s = FUN(:not_in, :zip, "60614", "60615")

    print(render(s))
    #-> ("zip" NOT IN ('60614', '60615'))

    s = SELECT(FUN(:not_in, "60615", FROM(:location) |> SELECT(:zip)))

    print(render(s))
    #=>
    SELECT ('60615' NOT IN (
      SELECT "zip"
      FROM "location"
    ))
    =#

    s = SELECT(FUN(:exists, FROM(:location) |>
                            WHERE(FUN("=", :zip, "60615")) |>
                            SELECT(missing)))

    print(render(s))
    #=>
    SELECT (EXISTS (
      SELECT NULL
      FROM "location"
      WHERE ("zip" = '60615')
    ))
    =#

    s = SELECT(FUN(:not_exists, FROM(:location) |>
                                WHERE(FUN("=", :zip, "60615")) |>
                                SELECT(missing)))

    print(render(s))
    #=>
    SELECT (NOT EXISTS (
      SELECT NULL
      FROM "location"
      WHERE ("zip" = '60615')
    ))
    =#

    s = FUN(:is_null, :zip)

    print(render(s))
    #-> ("zip" IS NULL)

    s = FUN(:is_not_null, :zip)

    print(render(s))
    #-> ("zip" IS NOT NULL)

    s = FUN(:like, :zip, "606%")

    print(render(s))
    #-> ("zip" LIKE '606%')

    s = FUN(:not_like, :zip, "606%")

    print(render(s))
    #-> ("zip" NOT LIKE '606%')

    s = FUN(:case, FUN("<", :year_of_birth, 1970), "boomer")

    print(render(s))
    #-> (CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' END)

    s = FUN(:case, FUN("<", :year_of_birth, 1970), "boomer", "millenial")

    print(render(s))
    #-> (CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' ELSE 'millenial' END)

    s = FUN(:cast, "2020-01-01", "DATE")

    print(render(s))
    #-> CAST('2020-01-01' AS DATE)

    s = FUN(:extract, "YEAR", s)

    print(render(s))
    #-> EXTRACT(YEAR FROM CAST('2020-01-01' AS DATE))

    s = FUN(:between, :year_of_birth, 1950, 2000)

    print(render(s))
    #-> ("year_of_birth" BETWEEN 1950 AND 2000)

    s = FUN(:not_between, :year_of_birth, 1950, 2000)

    print(render(s))
    #-> ("year_of_birth" NOT BETWEEN 1950 AND 2000)

    s = FUN(:current_date)

    print(render(s))
    #-> CURRENT_DATE

    s = FUN(:current_date, 1)

    print(render(s))
    #-> CURRENT_DATE(1)

    s = FUN(:current_timestamp)

    print(render(s))
    #-> CURRENT_TIMESTAMP


## Aggregate Functions

Aggregate SQL functions have a specialized `AGG()` constructor.

    s = AGG(:max, :year_of_birth)
    #-> AGG("max", …)

    display(s)
    #-> AGG("max", ID(:year_of_birth))

    print(render(s))
    #-> max("year_of_birth")

Some well-known aggregate functions with irregular syntax are supported.

    s = AGG(:count)
    #-> AGG("count")

    display(s)
    #-> AGG("count")

    print(render(s))
    #-> count(*)

    s = AGG(:count_distinct, :zip)

    print(render(s))
    #-> count(DISTINCT "zip")

Otherwise, a template name can be used.

    s = AGG("string_agg(DISTINCT ?, ',' ORDER BY ?)", :zip, :zip)

    print(render(s))
    #-> string_agg(DISTINCT "zip", ',' ORDER BY "zip")

An aggregate function may have a `FILTER` modifier.

    s = AGG(:count, filter = FUN(">", :year_of_birth, 1970))

    display(s)
    #-> AGG("count", filter = FUN(">", ID(:year_of_birth), LIT(1970)))

    print(render(s))
    #-> (count(*) FILTER (WHERE ("year_of_birth" > 1970)))

A window function can be created by adding an `OVER` modifier.

    s = AGG("row_number", over = PARTITION(:year_of_birth, order_by = [:month_of_birth, :day_of_birth]))

    display(s)
    #=>
    AGG("row_number",
        over = PARTITION(ID(:year_of_birth),
                         order_by = [ID(:month_of_birth), ID(:day_of_birth)]))
    =#

    print(render(s))
    #-> (row_number() OVER (PARTITION BY "year_of_birth" ORDER BY "month_of_birth", "day_of_birth"))

    s = AGG("row_number", over = :w)

    print(render(s))
    #-> (row_number() OVER ("w"))

The `PARTITION` clause may contain a frame specification including the frame
mode, frame endpoints, and frame exclusion.

    s = PARTITION(order_by = [:year_of_birth], frame = :groups)
    #-> PARTITION(order_by = […], frame = :GROUPS)

    print(render(s))
    #-> ORDER BY "year_of_birth" GROUPS UNBOUNDED PRECEDING

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :rows,))
    #-> PARTITION(order_by = […], frame = :ROWS)

    print(render(s))
    #-> ORDER BY "year_of_birth" ROWS UNBOUNDED PRECEDING

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, start = -1, finish = 1, exclude = :current_row))
    #-> PARTITION(order_by = […], frame = (mode = :RANGE, start = -1, finish = 1, exclude = :CURRENT_ROW))

    print(render(s))
    #-> ORDER BY "year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING EXCLUDE CURRENT ROW

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, start = -Inf, finish = 0))

    print(render(s))
    #-> ORDER BY "year_of_birth" RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, start = 0, finish = Inf))

    print(render(s))
    #-> ORDER BY "year_of_birth" RANGE BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, exclude = :no_others))

    print(render(s))
    #-> ORDER BY "year_of_birth" RANGE UNBOUNDED PRECEDING EXCLUDE NO OTHERS

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, exclude = :group))

    print(render(s))
    #-> ORDER BY "year_of_birth" RANGE UNBOUNDED PRECEDING EXCLUDE GROUP

    s = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, exclude = :ties))

    print(render(s))
    #-> ORDER BY "year_of_birth" RANGE UNBOUNDED PRECEDING EXCLUDE TIES


## `AS` Clause

An `AS` clause is created with `AS()` constructor.

    s = ID(:person) |> AS(:p)
    #-> (…) |> AS(:p)

    display(s)
    #-> ID(:person) |> AS(:p)

    print(render(s))
    #-> "person" AS "p"

A pair expression is automatically converted to an `AS` clause.

    s = FROM(:p => :person)
    display(s)
    #-> ID(:person) |> AS(:p) |> FROM()

    print(render(s |> SELECT((:p, :person_id))))
    #=>
    SELECT "p"."person_id"
    FROM "person" AS "p"
    =#


## `FROM` Clause

A `FROM` clause is created with `FROM()` constructor.

    s = FROM(:person)
    #-> (…) |> FROM()

    display(s)
    #-> ID(:person) |> FROM()

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    =#


## `SELECT` Clause

A `SELECT` clause is created with `SELECT()` constructor.  While in SQL,
`SELECT` typically opens a query, in FunSQL, `SELECT()` should be placed
at the end of a clause chain.

    s = :person |> FROM() |> SELECT(:person_id, :year_of_birth)
    #-> (…) |> SELECT(…)

    display(s)
    #-> ID(:person) |> FROM() |> SELECT(ID(:person_id), ID(:year_of_birth))

    print(render(s))
    #=>
    SELECT
      "person_id",
      "year_of_birth"
    FROM "person"
    =#

The `DISTINCT` modifier can be added from the constructor.

    s = FROM(:location) |> SELECT(distinct = true, :zip)
    #-> (…) |> SELECT(…)

    display(s)
    #-> ID(:location) |> FROM() |> SELECT(distinct = true, ID(:zip))

    print(render(s))
    #=>
    SELECT DISTINCT "zip"
    FROM "location"
    =#

A `TOP` modifier could be specified.

    s = FROM(:person) |> SELECT(top = 1, :person_id)

    display(s)
    #-> ID(:person) |> FROM() |> SELECT(top = 1, ID(:person_id))

    print(render(s))
    #=>
    SELECT TOP 1 "person_id"
    FROM "person"
    =#

    s = FROM(:person) |>
        ORDER(:year_of_birth) |>
        SELECT(top = (limit = 1, with_ties = true), :person_id)

    display(s)
    #=>
    ID(:person) |>
    FROM() |>
    ORDER(ID(:year_of_birth)) |>
    SELECT(top = (limit = 1, with_ties = true), ID(:person_id))
    =#

    print(render(s))
    #=>
    SELECT TOP 1 WITH TIES "person_id"
    FROM "person"
    ORDER BY "year_of_birth"
    =#

A `SELECT` clause with an empty list of arguments can be created explicitly.

    s = SELECT(args = [])
    #-> SELECT(…)

Rendering a nested `SELECT` clause adds parentheses around it.

    s = :location |> FROM() |> SELECT(:state, :zip) |> FROM() |> SELECT(:zip)

    print(render(s))
    #=>
    SELECT "zip"
    FROM (
      SELECT
        "state",
        "zip"
      FROM "location"
    )
    =#


## `WHERE` Clause

A `WHERE` clause is created with `WHERE()` constructor.

    s = FROM(:person) |> WHERE(FUN(">", :year_of_birth, 2000))
    #-> (…) |> WHERE(…)

    display(s)
    #-> ID(:person) |> FROM() |> WHERE(FUN(">", ID(:year_of_birth), LIT(2000)))

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE ("year_of_birth" > 2000)
    =#


## `LIMIT` Clause

A `LIMIT/OFFSET` (or `OFFSET/FETCH`) clause is created with `LIMIT()`
constructor.

    s = FROM(:person) |> LIMIT(10)
    #-> (…) |> LIMIT(10)

    display(s)
    #-> ID(:person) |> FROM() |> LIMIT(10)

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    FETCH FIRST 10 ROWS ONLY
    =#

Many SQL dialects represent `LIMIT` clause with a non-standard syntax.

    print(render(s |> SELECT(:person_id), dialect = :mysql))
    #=>
    SELECT `person_id`
    FROM `person`
    LIMIT 10
    =#

    print(render(s |> SELECT(:person_id), dialect = :postgresql))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT 10
    =#

    print(render(s |> SELECT(:person_id), dialect = :sqlite))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT 10
    =#

    print(render(s |> SELECT(:person_id), dialect = :sqlserver))
    #=>
    SELECT TOP 10 [person_id]
    FROM [person]
    =#

Both limit (the number of rows) and offset (number of rows to skip) can
be specified.

    s = FROM(:person) |> LIMIT(100, 10) |> SELECT(:person_id)

    display(s)
    #-> ID(:person) |> FROM() |> LIMIT(100, 10) |> SELECT(ID(:person_id))

    print(render(s))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

    print(render(s, dialect = :mysql))
    #=>
    SELECT `person_id`
    FROM `person`
    LIMIT 100, 10
    =#

    print(render(s, dialect = :postgresql))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT 10
    OFFSET 100
    =#

    print(render(s, dialect = :sqlite))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT 10
    OFFSET 100
    =#

    print(render(s, dialect = :sqlserver))
    #=>
    SELECT [person_id]
    FROM [person]
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

Alternatively, both limit and offset can be specified as a unit range.

    s = FROM(:person) |> LIMIT(101:110)

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

It is possible to specify the offset without the limit.

    s = FROM(:person) |> LIMIT(offset = 100) |> SELECT(:person_id)

    display(s)
    #-> ID(:person) |> FROM() |> LIMIT(100, nothing) |> SELECT(ID(:person_id))

    print(render(s))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100 ROWS
    =#

    print(render(s, dialect = :mysql))
    #=>
    SELECT `person_id`
    FROM `person`
    LIMIT 100, 18446744073709551615
    =#

    print(render(s, dialect = :postgresql))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100
    =#

    print(render(s, dialect = :sqlite))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT -1
    OFFSET 100
    =#

    print(render(s, dialect = :sqlserver))
    #=>
    SELECT [person_id]
    FROM [person]
    OFFSET 100 ROWS
    =#

It is possible to specify the limit with ties.

    s = FROM(:person) |>
        ORDER(:year_of_birth) |>
        LIMIT(10, with_ties = true) |>
        SELECT(:person_id)

    display(s)
    #=>
    ID(:person) |>
    FROM() |>
    ORDER(ID(:year_of_birth)) |>
    LIMIT(10, with_ties = true) |>
    SELECT(ID(:person_id))
    =#

    print(render(s))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY "year_of_birth"
    FETCH FIRST 10 ROWS WITH TIES
    =#

SQL Server prohibits `ORDER BY` without limiting in a nested query, so FunSQL
automatically adds `OFFSET 0` clause to the query.

    s = FROM(:person) |>
        ORDER(:year_of_birth) |>
        SELECT(:person_id, :gender_concept_id) |>
        AS(:person) |>
        FROM() |>
        WHERE(FUN("=", :gender_concept_id, 8507)) |>
        SELECT(:person_id)

    print(render(s, dialect = :sqlserver))
    #=>
    SELECT [person_id]
    FROM (
      SELECT
        [person_id],
        [gender_concept_id]
      FROM [person]
      ORDER BY [year_of_birth]
      OFFSET 0 ROWS
    ) AS [person]
    WHERE ([gender_concept_id] = 8507)
    =#


## `JOIN` Clause

A `JOIN` clause is created with `JOIN()` constructor.

    s = FROM(:p => :person) |>
        JOIN(:l => :location, FUN("=", (:p, :location_id), (:l, :location_id)), left = true)
    #-> (…) |> JOIN(…)

    display(s)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:location) |> AS(:l),
         FUN("=", ID(:p) |> ID(:location_id), ID(:l) |> ID(:location_id)),
         left = true)
    =#

    print(render(s |> SELECT((:p, :person_id), (:l, :state))))
    #=>
    SELECT
      "p"."person_id",
      "l"."state"
    FROM "person" AS "p"
    LEFT JOIN "location" AS "l" ON ("p"."location_id" = "l"."location_id")
    =#

Different types of `JOIN` are supported.

    s = FROM(:p => :person) |>
        JOIN(:op => :observation_period,
             on = FUN("=", (:p, :person_id), (:op, :person_id)))

    display(s)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:observation_period) |> AS(:op),
         FUN("=", ID(:p) |> ID(:person_id), ID(:op) |> ID(:person_id)))
    =#

    print(render(s |> SELECT((:p, :person_id), (:op, :observation_period_start_date))))
    #=>
    SELECT
      "p"."person_id",
      "op"."observation_period_start_date"
    FROM "person" AS "p"
    JOIN "observation_period" AS "op" ON ("p"."person_id" = "op"."person_id")
    =#

    s = FROM(:l => :location) |>
        JOIN(:cs => :care_site,
             on = FUN("=", (:l, :location_id), (:cs, :location_id)),
             right = true)

    display(s)
    #=>
    ID(:location) |>
    AS(:l) |>
    FROM() |>
    JOIN(ID(:care_site) |> AS(:cs),
         FUN("=", ID(:l) |> ID(:location_id), ID(:cs) |> ID(:location_id)),
         right = true)
    =#

    print(render(s |> SELECT((:cs, :care_site_name), (:l, :state))))
    #=>
    SELECT
      "cs"."care_site_name",
      "l"."state"
    FROM "location" AS "l"
    RIGHT JOIN "care_site" AS "cs" ON ("l"."location_id" = "cs"."location_id")
    =#

    s = FROM(:p => :person) |>
        JOIN(:pr => :provider,
             on = FUN("=", (:p, :provider_id), (:pr, :provider_id)),
             left = true,
             right = true)

    display(s)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:provider) |> AS(:pr),
         FUN("=", ID(:p) |> ID(:provider_id), ID(:pr) |> ID(:provider_id)),
         left = true,
         right = true)
    =#

    print(render(s |> SELECT((:p, :person_id), (:pr, :npi))))
    #=>
    SELECT
      "p"."person_id",
      "pr"."npi"
    FROM "person" AS "p"
    FULL JOIN "provider" AS "pr" ON ("p"."provider_id" = "pr"."provider_id")
    =#

To render a `CROSS JOIN`, set the join condition to `true`.

    s = FROM(:p1 => :person) |>
        JOIN(:p2 => :person,
             on = true)

    print(render(s |> SELECT((:p1, :person_id), (:p2, :person_id))))
    #=>
    SELECT
      "p1"."person_id",
      "p2"."person_id"
    FROM "person" AS "p1"
    CROSS JOIN "person" AS "p2"
    =#

A `JOIN LATERAL` clause can be created.

    s = FROM(:p => :person) |>
        JOIN(:vo => FROM(:vo => :visit_occurrence) |>
                    WHERE(FUN("=", (:p, :person_id), (:vo, :person_id))) |>
                    ORDER((:vo, :visit_start_date) |> DESC()) |>
                    LIMIT(1) |>
                    SELECT((:vo, :visit_start_date)),
             on = true,
             left = true,
             lateral = true)

    display(s)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:visit_occurrence) |>
         AS(:vo) |>
         FROM() |>
         WHERE(FUN("=", ID(:p) |> ID(:person_id), ID(:vo) |> ID(:person_id))) |>
         ORDER(ID(:vo) |> ID(:visit_start_date) |> DESC()) |>
         LIMIT(1) |>
         SELECT(ID(:vo) |> ID(:visit_start_date)) |>
         AS(:vo),
         LIT(true),
         left = true,
         lateral = true)
    =#

    print(render(s |> SELECT((:p, :person_id), (:vo, :visit_start_date))))
    #=>
    SELECT
      "p"."person_id",
      "vo"."visit_start_date"
    FROM "person" AS "p"
    LEFT JOIN LATERAL (
      SELECT "vo"."visit_start_date"
      FROM "visit_occurrence" AS "vo"
      WHERE ("p"."person_id" = "vo"."person_id")
      ORDER BY "vo"."visit_start_date" DESC
      FETCH FIRST 1 ROW ONLY
    ) AS "vo" ON TRUE
    =#


## `GROUP` Clause

A `GROUP BY` clause is created with `GROUP` constructor.

    s = FROM(:person) |> GROUP(:year_of_birth)
    #-> (…) |> GROUP(…)

    display(s)
    #-> ID(:person) |> FROM() |> GROUP(ID(:year_of_birth))

    print(render(s |> SELECT(:year_of_birth, AGG(:count))))
    #=>
    SELECT
      "year_of_birth",
      count(*)
    FROM "person"
    GROUP BY "year_of_birth"
    =#

A `GROUP` constructor accepts an empty partition list, in which case, it is not
rendered.

    s = FROM(:person) |> GROUP()
    #-> (…) |> GROUP()

    print(render(s |> SELECT(AGG(:count))))
    #=>
    SELECT count(*)
    FROM "person"
    =#

`GROUP` can accept the grouping mode or a vector of grouping sets.

    s = FROM(:person) |> GROUP(:year_of_birth, sets = :ROLLUP)
    #-> (…) |> GROUP(…, sets = :ROLLUP)

    print(render(s |> SELECT(:year_of_birth, AGG(:count))))
    #=>
    SELECT
      "year_of_birth",
      count(*)
    FROM "person"
    GROUP BY ROLLUP("year_of_birth")
    =#

    s = FROM(:person) |> GROUP(:year_of_birth, sets = :CUBE)
    #-> (…) |> GROUP(…, sets = :CUBE)

    print(render(s |> SELECT(:year_of_birth, AGG(:count))))
    #=>
    SELECT
      "year_of_birth",
      count(*)
    FROM "person"
    GROUP BY CUBE("year_of_birth")
    =#

    s = FROM(:person) |> GROUP(:year_of_birth, sets = [[1], Int[]])
    #-> (…) |> GROUP(…, sets = [[1], Int64[]])

    print(render(s |> SELECT(:year_of_birth, AGG(:count))))
    #=>
    SELECT
      "year_of_birth",
      count(*)
    FROM "person"
    GROUP BY GROUPING SETS(("year_of_birth"), ())
    =#

`GROUP` raises an error when the vector of grouping sets is out of bounds.

    FROM(:person) |> GROUP(:year_of_birth, sets = [[1, 2], [1], Int[]])
    #=>
    ERROR: DomainError with [[1, 2], [1], Int64[]]:
    sets are out of bounds
    =#


## `HAVING` Clause

A `HAVING` clause is created with `HAVING()` constructor.

    s = FROM(:person) |>
        GROUP(:year_of_birth) |>
        HAVING(FUN(">", AGG(:count), 10))
    #-> (…) |> HAVING(…)

    display(s)
    #=>
    ID(:person) |>
    FROM() |>
    GROUP(ID(:year_of_birth)) |>
    HAVING(FUN(">", AGG("count"), LIT(10)))
    =#

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    GROUP BY "year_of_birth"
    HAVING (count(*) > 10)
    =#


## `ORDER` Clause

An `ORDER BY` clause is created with `ORDER` constructor.

    s = FROM(:person) |> ORDER(:year_of_birth)
    #-> (…) |> ORDER(…)

    display(s)
    #-> ID(:person) |> FROM() |> ORDER(ID(:year_of_birth))

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY "year_of_birth"
    =#

An `ORDER` constructor accepts an empty list, in which case, it is not
rendered.

    s = FROM(:person) |> ORDER()
    #-> (…) |> ORDER()

    print(render(s |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    =#

It is possible to specify ascending or descending order of the sort column.

    s = FROM(:person) |>
        ORDER(:year_of_birth |> DESC(nulls = :first),
              :person_id |> ASC()) |>
        SELECT(:person_id)

    display(s)
    #=>
    ID(:person) |>
    FROM() |>
    ORDER(ID(:year_of_birth) |> DESC(nulls = :NULLS_FIRST),
          ID(:person_id) |> ASC()) |>
    SELECT(ID(:person_id))
    =#

    print(render(s))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY
      "year_of_birth" DESC NULLS FIRST,
      "person_id" ASC
    =#

Instead of `ASC` and `DESC`, a generic `SORT` constructor can be used.

    s = FROM(:person) |>
        ORDER(:year_of_birth |> SORT(:desc, nulls = :last),
              :person_id |> SORT(:asc)) |>
        SELECT(:person_id)

    print(render(s))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY
      "year_of_birth" DESC NULLS LAST,
      "person_id" ASC
    =#


## `UNION` Clause.

`UNION` and `UNION ALL` clauses are created with `UNION()` constructor.

    s = FROM(:measurement) |>
        SELECT(:person_id, :date => :measurement_date) |>
        UNION(all = true,
              FROM(:observation) |>
              SELECT(:person_id, :date => :observation_date))
    #-> (…) |> UNION(all = true, …)

    display(s)
    #=>
    ID(:measurement) |>
    FROM() |>
    SELECT(ID(:person_id), ID(:measurement_date) |> AS(:date)) |>
    UNION(all = true,
          ID(:observation) |>
          FROM() |>
          SELECT(ID(:person_id), ID(:observation_date) |> AS(:date)))
    =#

    print(render(s))
    #=>
    SELECT
      "person_id",
      "measurement_date" AS "date"
    FROM "measurement"
    UNION ALL
    SELECT
      "person_id",
      "observation_date" AS "date"
    FROM "observation"
    =#

A `UNION` clause with no subqueries can be created explicitly.

    UNION(args = [])
    #-> UNION(args = [])

Rendering a nested `UNION` clause adds parentheses around it.

    s = FROM(:measurement) |>
        SELECT(:person_id, :date => :measurement_date) |>
        UNION(all = true,
              FROM(:observation) |>
              SELECT(:person_id, :date => :observation_date)) |>
        FROM() |>
        AS(:union) |>
        WHERE(FUN(">", ID(:date), Date(2000))) |>
        SELECT(ID(:person_id))

    print(render(s))
    #=>
    SELECT "person_id"
    FROM (
      SELECT
        "person_id",
        "measurement_date" AS "date"
      FROM "measurement"
      UNION ALL
      SELECT
        "person_id",
        "observation_date" AS "date"
      FROM "observation"
    ) AS "union"
    WHERE ("date" > '2000-01-01')
    =#


## `VALUES` Clause

A `VALUES` clause is created with `VALUES()` constructor.

    s = VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)])
    #-> VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)])

    display(s)
    #-> VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)])

    print(render(s))
    #=>
    VALUES
      ('SQL', 1974),
      ('Julia', 2012),
      ('FunSQL', 2021)
    =#

MySQL has special syntax for rows.

    print(render(s, dialect = :mysql))
    #=>
    VALUES
      ROW('SQL', 1974),
      ROW('Julia', 2012),
      ROW('FunSQL', 2021)
    =#

When `VALUES` clause contains a single row, it is emitted on the same
line.

    s = VALUES([("SQL", 1974)])

    print(render(s))
    #-> VALUES ('SQL', 1974)

`VALUES` accepts a vector of scalar values.

    s = VALUES(["SQL", "Julia", "FunSQL"])

    print(render(s))
    #=>
    VALUES
      'SQL',
      'Julia',
      'FunSQL'
    =#

When `VALUES` is nested in a `FROM` clause, it is wrapped in parentheses.

    s = VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)]) |>
        AS(:values, columns = [:name, :year]) |>
        FROM() |>
        SELECT(FUN("*"))

    print(render(s))
    #=>
    SELECT *
    FROM (
      VALUES
        ('SQL', 1974),
        ('Julia', 2012),
        ('FunSQL', 2021)
    ) AS "values" ("name", "year")
    =#


## `WINDOW` Clause

A `WINDOW` clause is created with `WINDOW()` constructor.

    s = FROM(:person) |>
        WINDOW(:w1 => PARTITION(:gender_concept_id),
               :w2 => :w1 |> PARTITION(:year_of_birth, order_by = [:month_of_birth, :day_of_birth]))
    #-> (…) |> WINDOW(…)

    display(s)
    #=>
    ID(:person) |>
    FROM() |>
    WINDOW(PARTITION(ID(:gender_concept_id)) |> AS(:w1),
           ID(:w1) |>
           PARTITION(ID(:year_of_birth),
                     order_by = [ID(:month_of_birth), ID(:day_of_birth)]) |>
           AS(:w2))
    =#

    print(render(s |> SELECT(AGG("row_number", over = :w1), AGG("row_number", over = :w2))))
    #=>
    SELECT
      (row_number() OVER ("w1")),
      (row_number() OVER ("w2"))
    FROM "person"
    WINDOW
      "w1" AS (PARTITION BY "gender_concept_id"),
      "w2" AS ("w1" PARTITION BY "year_of_birth" ORDER BY "month_of_birth", "day_of_birth")
    =#

The `WINDOW()` constructor accepts an empty list of partitions, in which case,
it is not rendered.

    s = FROM(:person) |>
        WINDOW(args = [])

    display(s)
    #-> ID(:person) |> FROM() |> WINDOW(args = [])

    print(render(s |> SELECT(AGG("row_number", over = PARTITION()))))
    #=>
    SELECT (row_number() OVER ())
    FROM "person"
    =#


## `WITH` Clause and Common Table Expressions

The `AS` clause that defines a common table expression is created using the
`AS` constructor.

    cte1 =
        FROM(:concept) |>
        WHERE(FUN("=", :concept_id, 320128)) |>
        SELECT(:concept_id, :concept_name) |>
        AS(:essential_hypertension)
    #-> (…) |> AS(:essential_hypertension)

    cte2 =
        FROM(:essential_hypertension) |>
        SELECT(:concept_id, :concept_name) |>
        UNION(all = true,
              FROM(:eh => :essential_hypertension_with_descendants) |>
              JOIN(:cr => :concept_relationship,
                   FUN("=", (:eh, :concept_id), (:cr, :concept_id_1))) |>
              JOIN(:c => :concept,
                   FUN("=", (:cr, :concept_id_2), (:c, :concept_id))) |>
              WHERE(FUN("=", (:cr, :relationship_id), "Subsumes")) |>
              SELECT((:c, :concept_id), (:c, :concept_name))) |>
        AS(:essential_hypertension_with_descendants,
            columns = [:concept_id, :concept_name])
    #-> (…) |> AS(:essential_hypertension_with_descendants, columns = […])

The `WITH` clause is created using the `WITH()` constructor.

    s = FROM(:essential_hypertension_with_descendants) |>
        SELECT(*) |>
        WITH(recursive = true, cte1, cte2)
    #-> (…) |> WITH(recursive = true, …)

    display(s)
    #=>
    ID(:essential_hypertension_with_descendants) |>
    FROM() |>
    SELECT(FUN("*")) |>
    WITH(recursive = true,
         ID(:concept) |>
         FROM() |>
         WHERE(FUN("=", ID(:concept_id), LIT(320128))) |>
         SELECT(ID(:concept_id), ID(:concept_name)) |>
         AS(:essential_hypertension),
         ID(:essential_hypertension) |>
         FROM() |>
         SELECT(ID(:concept_id), ID(:concept_name)) |>
         UNION(all = true,
               ID(:essential_hypertension_with_descendants) |>
               AS(:eh) |>
               FROM() |>
               JOIN(ID(:concept_relationship) |> AS(:cr),
                    FUN("=",
                        ID(:eh) |> ID(:concept_id),
                        ID(:cr) |> ID(:concept_id_1))) |>
               JOIN(ID(:concept) |> AS(:c),
                    FUN("=",
                        ID(:cr) |> ID(:concept_id_2),
                        ID(:c) |> ID(:concept_id))) |>
               WHERE(FUN("=", ID(:cr) |> ID(:relationship_id), LIT("Subsumes"))) |>
               SELECT(ID(:c) |> ID(:concept_id), ID(:c) |> ID(:concept_name))) |>
         AS(:essential_hypertension_with_descendants,
            columns = [:concept_id, :concept_name]))
    =#

    print(render(s))
    #=>
    WITH RECURSIVE "essential_hypertension" AS (
      SELECT
        "concept_id",
        "concept_name"
      FROM "concept"
      WHERE ("concept_id" = 320128)
    ),
    "essential_hypertension_with_descendants" ("concept_id", "concept_name") AS (
      SELECT
        "concept_id",
        "concept_name"
      FROM "essential_hypertension"
      UNION ALL
      SELECT
        "c"."concept_id",
        "c"."concept_name"
      FROM "essential_hypertension_with_descendants" AS "eh"
      JOIN "concept_relationship" AS "cr" ON ("eh"."concept_id" = "cr"."concept_id_1")
      JOIN "concept" AS "c" ON ("cr"."concept_id_2" = "c"."concept_id")
      WHERE ("cr"."relationship_id" = 'Subsumes')
    )
    SELECT *
    FROM "essential_hypertension_with_descendants"
    =#

The `MATERIALIZED` annotation can be added using `NOTE`.

    cte =
        FROM(:condition_occurrence) |>
        WHERE(FUN("=", :condition_concept_id, 320128)) |>
        SELECT(:person_id) |>
        NOTE("MATERIALIZED") |>
        AS(:essential_hypertension_occurrence)
    #-> (…) |> AS(:essential_hypertension_occurrence)

    display(cte)
    #=>
    ID(:condition_occurrence) |>
    FROM() |>
    WHERE(FUN("=", ID(:condition_concept_id), LIT(320128))) |>
    SELECT(ID(:person_id)) |>
    NOTE("MATERIALIZED") |>
    AS(:essential_hypertension_occurrence)
    =#

    print(render(FROM(:essential_hypertension_occurrence) |> SELECT(*) |> WITH(cte)))
    #=>
    WITH "essential_hypertension_occurrence" AS MATERIALIZED (
      SELECT "person_id"
      FROM "condition_occurrence"
      WHERE ("condition_concept_id" = 320128)
    )
    SELECT *
    FROM "essential_hypertension_occurrence"
    =#

A `WITH` clause without any common table expressions will be omitted.

    s = FROM(:condition_occurrence) |>
        SELECT(*) |>
        WITH(args = [])
    #-> (…) |> WITH(args = [])

    print(render(s))
    #=>
    SELECT *
    FROM "condition_occurrence"
    =#
