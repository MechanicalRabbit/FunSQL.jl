# SQL Clauses

    using FunSQL:
        AGG, AS, ASC, DESC, FROM, FUN, GROUP, HAVING, ID, JOIN, LIMIT, LIT,
        NOTE, ORDER, PARTITION, SELECT, SORT, UNION, VALUES, VAR, WHERE,
        WINDOW, WITH, pack, render

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
    SELECT
      "person_id",
      "year_of_birth"
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

    display(c)
    #=>
    SELECT(LIT(missing),
           LIT(true),
           LIT(42),
           LIT("SQL is fun!"),
           LIT(Dates.Date("2000-01-01")))
    =#

    print(render(c))
    #=>
    SELECT
      NULL,
      TRUE,
      42,
      'SQL is fun!',
      '2000-01-01'
    =#

Some values may render differently depending on the dialect.

    c = LIT(false)

    print(render(c, dialect = :sqlserver))
    #-> (1 = 0)

A quote character in a string literal is represented by a pair of quotes.

    c = LIT("O'Hare")

    print(render(c))
    #-> 'O''Hare'


## SQL Identifiers

A SQL identifier is created with `ID()` constructor.

    c = ID(:person)
    #-> ID(:person)

    display(c)
    #-> ID(:person)

    print(render(c))
    #-> "person"

Serialization of an identifier depends on the SQL dialect.

    print(render(c, dialect = :sqlserver))
    #-> [person]

A quote character in an identifier is properly escaped.

    c = ID("year of \"birth\"")

    print(render(c))
    #-> "year of ""birth"""

A qualified identifier is created using the chain operator.

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


## SQL Variables

Placeholder parameters to a SQL query are created with `VAR()` constructor.

    c = VAR(:YEAR)
    #-> VAR(:YEAR)

    display(c)
    #-> VAR(:YEAR)

    print(render(c))
    #-> :YEAR

Rendering of a SQL parameter depends on the chosen dialect.

    print(render(c, dialect = :sqlite))
    #-> ?1

    print(render(c, dialect = :postgresql))
    #-> $1

    print(render(c, dialect = :mysql))
    #-> ?

Function `pack()` converts named parameters to a positional form.

    c = FROM(:person) |>
        WHERE(FUN(:or, FUN("=", :gender_concept_id, VAR(:GENDER)),
                       FUN("=", :gender_source_concept_id, VAR(:GENDER)))) |>
        SELECT(:person_id)

    sql = render(c, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE (("gender_concept_id" = ?1) OR ("gender_source_concept_id" = ?1))
    =#

    pack(sql, (GENDER = 8532,))
    #-> Any[8532]

    pack(sql, Dict(:GENDER => 8532))
    #-> Any[8532]

    pack(sql, Dict("GENDER" => 8532))
    #-> Any[8532]

If the dialect does not support numbered parameters, `pack()` may need to
duplicate parameter values.

    sql = render(c, dialect = :mysql)

    print(sql)
    #=>
    SELECT `person_id`
    FROM `person`
    WHERE ((`gender_concept_id` = ?) OR (`gender_source_concept_id` = ?))
    =#

    pack(sql, (GENDER = 8532,))
    #-> Any[8532, 8532]


## SQL Functions and Operators

An application of a SQL function is created with `FUN()` constructor.

    c = FUN(:concat, :city, ", ", :state)
    #-> FUN("concat", …)

    display(c)
    #-> FUN("concat", ID(:city), LIT(", "), ID(:state))

    print(render(c))
    #-> concat("city", ', ', "state")

    c = FUN(:now)
    #-> FUN("now")

    print(render(c))
    #-> now()

`FUN()` with an empty name generates a comma-separated list of values.

    c = FUN("", "60614", "60615")

    print(render(c))
    #-> ('60614', '60615')

A name that contains only symbol characters is considered an operator.

    c = FUN("||", :city, ", ", :state)

    print(render(c))
    #-> ("city" || ', ' || "state")

To create an operator containing alphabetical characters, add a leading or a
trailing space to its name.

    c = FUN(" IS DISTINCT FROM ", :zip, missing)

    print(render(c))
    #-> ("zip" IS DISTINCT FROM NULL)

    c = FUN(" IS DISTINCT FROM", :zip, missing)

    print(render(c))
    #-> ("zip" IS DISTINCT FROM NULL)

    c = FUN(" COLLATE \"C\"", :zip)

    print(render(c))
    #-> ("zip" COLLATE "C")

    c = FUN("DATE ", "2000-01-01")

    print(render(c))
    #-> (DATE '2000-01-01')

    c = FUN("CURRENT_TIME ")

    print(render(c))
    #-> CURRENT_TIME

    c = FUN(" CURRENT_TIME")

    print(render(c))
    #-> CURRENT_TIME

To create a SQL expression with irregular syntax, supply `FUN()` with a
*template* string.

    c = FUN("SUBSTRING(? FROM ? FOR ?)", :zip, 1, 3)

    print(render(c))
    #-> SUBSTRING("zip" FROM 1 FOR 3)

    c = FUN("?::date", "2000-01-01")

    print(render(c))
    #-> '2000-01-01'::date

Write `??` to  use `?` in an operator name or a template.

    c = FUN("??-", "(1,0)", "(0,0)")

    print(render(c))
    #-> ('(1,0)' ?- '(0,0)')

    c = FUN("('(?,?)'::point ??| '(?,?)'::point)", 0, 1, 0, 0)

    print(render(c))
    #-> ('(0,1)'::point ?| '(0,0)'::point)

Some functions and operators have specialized serializers.

    c = FUN(:and)

    print(render(c))
    #-> TRUE

    c = FUN(:and, true)

    print(render(c))
    #-> TRUE

    c = FUN(:and, true, false)

    print(render(c))
    #-> (TRUE AND FALSE)

    c = FUN(:or)

    print(render(c))
    #-> FALSE

    c = FUN(:or, true)

    print(render(c))
    #-> TRUE

    c = FUN(:or, true, false)

    print(render(c))
    #-> (TRUE OR FALSE)

    c = FUN(:not, true)

    print(render(c))
    #-> (NOT TRUE)

    c = FUN(:concat, :city, ", ", :state)

    print(render(c))
    #-> concat("city", ', ', "state")

    print(render(c, dialect = :sqlite))
    #-> ("city" || ', ' || "state")

    c = FUN(:in, :zip)

    print(render(c))
    #-> FALSE

    c = FUN(:in, :zip, "60614", "60615")

    print(render(c))
    #-> ("zip" IN ('60614', '60615'))

    c = SELECT(FUN(:in, "60615", FROM(:location) |> SELECT(:zip)))

    print(render(c))
    #=>
    SELECT ('60615' IN (
      SELECT "zip"
      FROM "location"
    ))
    =#

    c = FUN(:not_in, :zip)

    print(render(c))
    #-> TRUE

    c = FUN(:not_in, :zip, "60614", "60615")

    print(render(c))
    #-> ("zip" NOT IN ('60614', '60615'))

    c = SELECT(FUN(:not_in, "60615", FROM(:location) |> SELECT(:zip)))

    print(render(c))
    #=>
    SELECT ('60615' NOT IN (
      SELECT "zip"
      FROM "location"
    ))
    =#

    c = SELECT(FUN(:exists, FROM(:location) |>
                            WHERE(FUN("=", :zip, "60615")) |>
                            SELECT(missing)))

    print(render(c))
    #=>
    SELECT (EXISTS (
      SELECT NULL
      FROM "location"
      WHERE ("zip" = '60615')
    ))
    =#

    c = SELECT(FUN(:not_exists, FROM(:location) |>
                                WHERE(FUN("=", :zip, "60615")) |>
                                SELECT(missing)))

    print(render(c))
    #=>
    SELECT (NOT EXISTS (
      SELECT NULL
      FROM "location"
      WHERE ("zip" = '60615')
    ))
    =#

    c = FUN(:is_null, :zip)

    print(render(c))
    #-> ("zip" IS NULL)

    c = FUN(:is_not_null, :zip)

    print(render(c))
    #-> ("zip" IS NOT NULL)

    c = FUN(:like, :zip, "606%")

    print(render(c))
    #-> ("zip" LIKE '606%')

    c = FUN(:not_like, :zip, "606%")

    print(render(c))
    #-> ("zip" NOT LIKE '606%')

    c = FUN(:case, FUN("<", :year_of_birth, 1970), "boomer")

    print(render(c))
    #-> (CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' END)

    c = FUN(:case, FUN("<", :year_of_birth, 1970), "boomer", "millenial")

    print(render(c))
    #-> (CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' ELSE 'millenial' END)

    c = FUN(:cast, "2020-01-01", "DATE")

    print(render(c))
    #-> CAST('2020-01-01' AS DATE)

    c = FUN(:extract, "YEAR", c)

    print(render(c))
    #-> EXTRACT(YEAR FROM CAST('2020-01-01' AS DATE))

    c = FUN(:between, :year_of_birth, 1950, 2000)

    print(render(c))
    #-> ("year_of_birth" BETWEEN 1950 AND 2000)

    c = FUN(:not_between, :year_of_birth, 1950, 2000)

    print(render(c))
    #-> ("year_of_birth" NOT BETWEEN 1950 AND 2000)

    c = FUN(:current_date)

    print(render(c))
    #-> CURRENT_DATE

    c = FUN(:current_timestamp)

    print(render(c))
    #-> CURRENT_TIMESTAMP


## Aggregate Functions

Aggregate SQL functions have a specialized `AGG()` constructor.

    c = AGG(:max, :year_of_birth)
    #-> AGG("max", …)

    display(c)
    #-> AGG("max", ID(:year_of_birth))

    print(render(c))
    #-> max("year_of_birth")

Some well-known aggregate functions with irregular syntax are supported.

    c = AGG(:count)
    #-> AGG("count")

    display(c)
    #-> AGG("count")

    print(render(c))
    #-> count(*)

    c = AGG(:count_distinct, :zip)

    print(render(c))
    #-> count(DISTINCT "zip")

Otherwise, a template name can be used.

    c = AGG("string_agg(DISTINCT ?, ',' ORDER BY ?)", :zip, :zip)

    print(render(c))
    #-> string_agg(DISTINCT "zip", ',' ORDER BY "zip")

An aggregate function may have a `FILTER` modifier.

    c = AGG(:count, filter = FUN(">", :year_of_birth, 1970))

    display(c)
    #-> AGG("count", filter = FUN(">", ID(:year_of_birth), LIT(1970)))

    print(render(c))
    #-> (count(*) FILTER (WHERE ("year_of_birth" > 1970)))

A window function can be created by adding an `OVER` modifier.

    c = PARTITION(:year_of_birth, order_by = [:month_of_birth, :day_of_birth]) |>
        AGG("row_number")

    display(c)
    #=>
    AGG("row_number",
        over = PARTITION(ID(:year_of_birth),
                         order_by = [ID(:month_of_birth), ID(:day_of_birth)]))
    =#

    print(render(c))
    #-> (row_number() OVER (PARTITION BY "year_of_birth" ORDER BY "month_of_birth", "day_of_birth"))

    c = AGG("row_number", over = :w)

    print(render(c))
    #-> (row_number() OVER ("w"))

The `PARTITION` clause may contain a frame specification including the frame
mode, frame endpoints, and frame exclusion.

    c = PARTITION(order_by = [:year_of_birth], frame = :groups)
    #-> PARTITION(order_by = […], frame = :GROUPS)

    print(render(c))
    #-> ORDER BY "year_of_birth" GROUPS UNBOUNDED PRECEDING

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :rows,))
    #-> PARTITION(order_by = […], frame = :ROWS)

    print(render(c))
    #-> ORDER BY "year_of_birth" ROWS UNBOUNDED PRECEDING

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, start = -1, finish = 1, exclude = :current_row))
    #-> PARTITION(order_by = […], frame = (mode = :RANGE, start = -1, finish = 1, exclude = :CURRENT_ROW))

    print(render(c))
    #-> ORDER BY "year_of_birth" RANGE BETWEEN 1 PRECEDING AND 1 FOLLOWING EXCLUDE CURRENT ROW

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, start = -Inf, finish = 0))

    print(render(c))
    #-> ORDER BY "year_of_birth" RANGE BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, start = 0, finish = Inf))

    print(render(c))
    #-> ORDER BY "year_of_birth" RANGE BETWEEN CURRENT ROW AND UNBOUNDED FOLLOWING

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, exclude = :no_others))

    print(render(c))
    #-> ORDER BY "year_of_birth" RANGE UNBOUNDED PRECEDING EXCLUDE NO OTHERS

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, exclude = :group))

    print(render(c))
    #-> ORDER BY "year_of_birth" RANGE UNBOUNDED PRECEDING EXCLUDE GROUP

    c = PARTITION(order_by = [:year_of_birth], frame = (mode = :range, exclude = :ties))

    print(render(c))
    #-> ORDER BY "year_of_birth" RANGE UNBOUNDED PRECEDING EXCLUDE TIES


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
    SELECT
      "person_id",
      "year_of_birth"
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

A `TOP` modifier could be specified.

    c = FROM(:person) |> SELECT(top = 1, :person_id)

    display(c)
    #-> ID(:person) |> FROM() |> SELECT(top = 1, ID(:person_id))

    print(render(c))
    #=>
    SELECT TOP 1 "person_id"
    FROM "person"
    =#

    c = FROM(:person) |>
        ORDER(:year_of_birth) |>
        SELECT(top = (limit = 1, with_ties = true), :person_id)

    display(c)
    #=>
    ID(:person) |>
    FROM() |>
    ORDER(ID(:year_of_birth)) |>
    SELECT(top = (limit = 1, with_ties = true), ID(:person_id))
    =#

    print(render(c))
    #=>
    SELECT TOP 1 WITH TIES "person_id"
    FROM "person"
    ORDER BY "year_of_birth"
    =#

A `SELECT` clause with an empty list of arguments can be created explicitly.

    c = SELECT(args = [])
    #-> SELECT(…)

Rendering a nested `SELECT` clause adds parentheses around it.

    c = :location |> FROM() |> SELECT(:state, :zip) |> FROM() |> SELECT(:zip)

    print(render(c))
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

    c = FROM(:person) |> WHERE(FUN(">", :year_of_birth, 2000))
    #-> (…) |> WHERE(…)

    display(c)
    #-> ID(:person) |> FROM() |> WHERE(FUN(">", ID(:year_of_birth), LIT(2000)))

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE ("year_of_birth" > 2000)
    =#


## `LIMIT` Clause

A `LIMIT/OFFSET` (or `OFFSET/FETCH`) clause is created with `LIMIT()`
constructor.

    c = FROM(:person) |> LIMIT(10)
    #-> (…) |> LIMIT(10)

    display(c)
    #-> ID(:person) |> FROM() |> LIMIT(10)

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    FETCH FIRST 10 ROWS ONLY
    =#

Non-standard MySQL and SQLite syntax is supported.

    print(render(c |> SELECT(:person_id), dialect = :mysql))
    #=>
    SELECT `person_id`
    FROM `person`
    LIMIT 10
    =#

    print(render(c |> SELECT(:person_id), dialect = :sqlite))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT 10
    =#


Both limit (the number of rows) and offset (number of rows to skip) can
be specified.

    c = FROM(:person) |> LIMIT(100, 10) |> SELECT(:person_id)

    display(c)
    #-> ID(:person) |> FROM() |> LIMIT(100, 10) |> SELECT(ID(:person_id))

    print(render(c))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

    print(render(c, dialect = :mysql))
    #=>
    SELECT `person_id`
    FROM `person`
    LIMIT 100, 10
    =#

    print(render(c, dialect = :sqlite))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT 10
    OFFSET 100
    =#

Alternatively, both limit and offset can be specified as a unit range.

    c = FROM(:person) |> LIMIT(101:110)

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100 ROWS
    FETCH NEXT 10 ROWS ONLY
    =#

It is possible to specify the offset without the limit.

    c = FROM(:person) |> LIMIT(offset = 100) |> SELECT(:person_id)

    display(c)
    #-> ID(:person) |> FROM() |> LIMIT(100, nothing) |> SELECT(ID(:person_id))

    print(render(c))
    #=>
    SELECT "person_id"
    FROM "person"
    OFFSET 100 ROWS
    =#

    print(render(c, dialect = :mysql))
    #=>
    SELECT `person_id`
    FROM `person`
    LIMIT 100, 18446744073709551615
    =#

    print(render(c, dialect = :sqlite))
    #=>
    SELECT "person_id"
    FROM "person"
    LIMIT -1
    OFFSET 100
    =#

It is possible to specify the limit with ties.

    c = FROM(:person) |>
        ORDER(:year_of_birth) |>
        LIMIT(10, with_ties = true) |>
        SELECT(:person_id)

    display(c)
    #=>
    ID(:person) |>
    FROM() |>
    ORDER(ID(:year_of_birth)) |>
    LIMIT(10, with_ties = true) |>
    SELECT(ID(:person_id))
    =#

    print(render(c))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY "year_of_birth"
    FETCH FIRST 10 ROWS WITH TIES
    =#


## `JOIN` Clause

A `JOIN` clause is created with `JOIN()` constructor.

    c = FROM(:p => :person) |>
        JOIN(:l => :location, FUN("=", (:p, :location_id), (:l, :location_id)), left = true)
    #-> (…) |> JOIN(…)

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:location) |> AS(:l),
         FUN("=", ID(:p) |> ID(:location_id), ID(:l) |> ID(:location_id)),
         left = true)
    =#

    print(render(c |> SELECT((:p, :person_id), (:l, :state))))
    #=>
    SELECT
      "p"."person_id",
      "l"."state"
    FROM "person" AS "p"
    LEFT JOIN "location" AS "l" ON ("p"."location_id" = "l"."location_id")
    =#

Different types of `JOIN` are supported.

    c = FROM(:p => :person) |>
        JOIN(:op => :observation_period,
             on = FUN("=", (:p, :person_id), (:op, :person_id)))

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:observation_period) |> AS(:op),
         FUN("=", ID(:p) |> ID(:person_id), ID(:op) |> ID(:person_id)))
    =#

    print(render(c |> SELECT((:p, :person_id), (:op, :observation_period_start_date))))
    #=>
    SELECT
      "p"."person_id",
      "op"."observation_period_start_date"
    FROM "person" AS "p"
    JOIN "observation_period" AS "op" ON ("p"."person_id" = "op"."person_id")
    =#

    c = FROM(:l => :location) |>
        JOIN(:cs => :care_site,
             on = FUN("=", (:l, :location_id), (:cs, :location_id)),
             right = true)

    display(c)
    #=>
    ID(:location) |>
    AS(:l) |>
    FROM() |>
    JOIN(ID(:care_site) |> AS(:cs),
         FUN("=", ID(:l) |> ID(:location_id), ID(:cs) |> ID(:location_id)),
         right = true)
    =#

    print(render(c |> SELECT((:cs, :care_site_name), (:l, :state))))
    #=>
    SELECT
      "cs"."care_site_name",
      "l"."state"
    FROM "location" AS "l"
    RIGHT JOIN "care_site" AS "cs" ON ("l"."location_id" = "cs"."location_id")
    =#

    c = FROM(:p => :person) |>
        JOIN(:pr => :provider,
             on = FUN("=", (:p, :provider_id), (:pr, :provider_id)),
             left = true,
             right = true)

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:provider) |> AS(:pr),
         FUN("=", ID(:p) |> ID(:provider_id), ID(:pr) |> ID(:provider_id)),
         left = true,
         right = true)
    =#

    print(render(c |> SELECT((:p, :person_id), (:pr, :npi))))
    #=>
    SELECT
      "p"."person_id",
      "pr"."npi"
    FROM "person" AS "p"
    FULL JOIN "provider" AS "pr" ON ("p"."provider_id" = "pr"."provider_id")
    =#

To render a `CROSS JOIN`, set the join condition to `true`.

    c = FROM(:p1 => :person) |>
        JOIN(:p2 => :person,
             on = true)

    print(render(c |> SELECT((:p1, :person_id), (:p2, :person_id))))
    #=>
    SELECT
      "p1"."person_id",
      "p2"."person_id"
    FROM "person" AS "p1"
    CROSS JOIN "person" AS "p2"
    =#

A `JOIN LATERAL` clause can be created.

    c = FROM(:p => :person) |>
        JOIN(:vo => FROM(:vo => :visit_occurrence) |>
                    WHERE(FUN("=", (:p, :person_id), (:vo, :person_id))) |>
                    ORDER((:vo, :visit_start_date) |> DESC()) |>
                    LIMIT(1) |>
                    SELECT((:vo, :visit_start_date)),
             on = true,
             left = true,
             lateral = true)

    display(c)
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

    print(render(c |> SELECT((:p, :person_id), (:vo, :visit_start_date))))
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

    c = FROM(:person) |> GROUP(:year_of_birth)
    #-> (…) |> GROUP(…)

    display(c)
    #-> ID(:person) |> FROM() |> GROUP(ID(:year_of_birth))

    print(render(c |> SELECT(:year_of_birth, AGG(:count))))
    #=>
    SELECT
      "year_of_birth",
      count(*)
    FROM "person"
    GROUP BY "year_of_birth"
    =#

A `GROUP` constructor accepts an empty partition list, in which case, it is not
rendered.

    c = FROM(:person) |> GROUP()
    #-> (…) |> GROUP()

    print(render(c |> SELECT(AGG(:count))))
    #=>
    SELECT count(*)
    FROM "person"
    =#


## `HAVING` Clause

A `HAVING` clause is created with `HAVING()` constructor.

    c = FROM(:person) |>
        GROUP(:year_of_birth) |>
        HAVING(FUN(">", AGG(:count), 10))
    #-> (…) |> HAVING(…)

    display(c)
    #=>
    ID(:person) |>
    FROM() |>
    GROUP(ID(:year_of_birth)) |>
    HAVING(FUN(">", AGG("count"), LIT(10)))
    =#

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    GROUP BY "year_of_birth"
    HAVING (count(*) > 10)
    =#


## `ORDER` Clause

An `ORDER BY` clause is created with `ORDER` constructor.

    c = FROM(:person) |> ORDER(:year_of_birth)
    #-> (…) |> ORDER(…)

    display(c)
    #-> ID(:person) |> FROM() |> ORDER(ID(:year_of_birth))

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY "year_of_birth"
    =#

An `ORDER` constructor accepts an empty list, in which case, it is not
rendered.

    c = FROM(:person) |> ORDER()
    #-> (…) |> ORDER()

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    =#

It is possible to specify ascending or descending order of the sort column.

    c = FROM(:person) |>
        ORDER(:year_of_birth |> DESC(nulls = :first),
              :person_id |> ASC()) |>
        SELECT(:person_id)

    display(c)
    #=>
    ID(:person) |>
    FROM() |>
    ORDER(ID(:year_of_birth) |> DESC(nulls = :NULLS_FIRST),
          ID(:person_id) |> ASC()) |>
    SELECT(ID(:person_id))
    =#

    print(render(c))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY
      "year_of_birth" DESC NULLS FIRST,
      "person_id" ASC
    =#

Instead of `ASC` and `DESC`, a generic `SORT` constructor can be used.

    c = FROM(:person) |>
        ORDER(:year_of_birth |> SORT(:desc, nulls = :first),
              :person_id |> SORT(:asc)) |>
        SELECT(:person_id)

    print(render(c))
    #=>
    SELECT "person_id"
    FROM "person"
    ORDER BY
      "year_of_birth" DESC NULLS FIRST,
      "person_id" ASC
    =#


## `UNION` Clause.

`UNION` and `UNION ALL` clauses are created with `UNION()` constructor.

    c = FROM(:measurement) |>
        SELECT(:person_id, :date => :measurement_date) |>
        UNION(all = true,
              FROM(:observation) |>
              SELECT(:person_id, :date => :observation_date))
    #-> (…) |> UNION(all = true, …)

    display(c)
    #=>
    ID(:measurement) |>
    FROM() |>
    SELECT(ID(:person_id), ID(:measurement_date) |> AS(:date)) |>
    UNION(all = true,
          ID(:observation) |>
          FROM() |>
          SELECT(ID(:person_id), ID(:observation_date) |> AS(:date)))
    =#

    print(render(c))
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

    c = FROM(:measurement) |>
        SELECT(:person_id, :date => :measurement_date) |>
        UNION(all = true,
              FROM(:observation) |>
              SELECT(:person_id, :date => :observation_date)) |>
        FROM() |>
        AS(:union) |>
        WHERE(FUN(">", ID(:date), Date(2000))) |>
        SELECT(ID(:person_id))

    print(render(c))
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

    c = VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)])
    #-> VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)])

    display(c)
    #-> VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)])

    print(render(c))
    #=>
    VALUES
      ('SQL', 1974),
      ('Julia', 2012),
      ('FunSQL', 2021)
    =#

MySQL has special syntax for rows.

    print(render(c, dialect = :mysql))
    #=>
    VALUES
      ROW('SQL', 1974),
      ROW('Julia', 2012),
      ROW('FunSQL', 2021)
    =#

When `VALUES` clause contains a single row, it is emitted on the same
line.

    c = VALUES([("SQL", 1974)])

    print(render(c))
    #-> VALUES ('SQL', 1974)

`VALUES` accepts a vector of scalar values.

    c = VALUES(["SQL", "Julia", "FunSQL"])

    print(render(c))
    #=>
    VALUES
      'SQL',
      'Julia',
      'FunSQL'
    =#

When `VALUES` is nested in a `FROM` clause, it is wrapped in parentheses.

    c = VALUES([("SQL", 1974), ("Julia", 2012), ("FunSQL", 2021)]) |>
        AS(:values, columns = [:name, :year]) |>
        FROM() |>
        SELECT(FUN("*"))

    print(render(c))
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

    c = FROM(:person) |>
        WINDOW(:w1 => PARTITION(:gender_concept_id),
               :w2 => :w1 |> PARTITION(:year_of_birth, order_by = [:month_of_birth, :day_of_birth]))
    #-> (…) |> WINDOW(…)

    display(c)
    #=>
    ID(:person) |>
    FROM() |>
    WINDOW(PARTITION(ID(:gender_concept_id)) |> AS(:w1),
           ID(:w1) |>
           PARTITION(ID(:year_of_birth),
                     order_by = [ID(:month_of_birth), ID(:day_of_birth)]) |>
           AS(:w2))
    =#

    print(render(c |> SELECT(:w1 |> AGG("ROW_NUMBER"), :w2 |> AGG("ROW_NUMBER"))))
    #=>
    SELECT
      (ROW_NUMBER() OVER ("w1")),
      (ROW_NUMBER() OVER ("w2"))
    FROM "person"
    WINDOW
      "w1" AS (PARTITION BY "gender_concept_id"),
      "w2" AS ("w1" PARTITION BY "year_of_birth" ORDER BY "month_of_birth", "day_of_birth")
    =#

The `WINDOW()` constructor accepts an empty list of partitions, in which case,
it is not rendered.

    c = FROM(:person) |>
        WINDOW(args = [])

    display(c)
    #-> ID(:person) |> FROM() |> WINDOW(args = [])

    print(render(c |> SELECT(AGG("ROW_NUMBER", over = PARTITION()))))
    #=>
    SELECT (ROW_NUMBER() OVER ())
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

    c = FROM(:essential_hypertension_with_descendants) |>
        SELECT(*) |>
        WITH(recursive = true, cte1, cte2)
    #-> (…) |> WITH(recursive = true, …)

    display(c)
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

    print(render(c))
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

    c = FROM(:condition_occurrence) |>
        SELECT(*) |>
        WITH(args = [])
    #-> (…) |> WITH(args = [])

    print(render(c))
    #=>
    SELECT *
    FROM "condition_occurrence"
    =#

