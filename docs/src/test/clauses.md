# SQL Clauses

    using FunSQL:
        AGG, AS, CASE, FROM, FUN, GROUP, HAVING, ID, JOIN, KW, LIMIT, LIT, OP,
        PARTITION, SELECT, UNION, VAR, WHERE, WINDOW, pack, render

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

Serialization of an identifier depends on the SQL dialect.

    print(render(c, dialect = :sqlserver))
    #-> [person]

A quoted identifier is created using the chain operator.

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

    c = VAR(:year)
    #-> VAR(:year)

    display(c)
    #-> VAR(:year)

    print(render(c))
    #-> :year

Rendering of a SQL parameter depends on the chosen dialect.

    print(render(c, dialect = :sqlite))
    #-> ?1

    print(render(c, dialect = :postgresql))
    #-> $1

    print(render(c, dialect = :mysql))
    #-> ?

Function `pack()` converts named parameters to a positional form.

    c = FROM(:person) |>
        WHERE(OP("OR", OP("=", :gender_concept_id, VAR(:gender)),
                       OP("=", :gender_source_concept_id, VAR(:gender)))) |>
        SELECT(:person_id)

    sql = render(c, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE (("gender_concept_id" = ?1) OR ("gender_source_concept_id" = ?1))
    =#

    pack(sql, (gender = 8532,))
    #-> Any[8532]

    pack(sql, Dict(:gender => 8532))
    #-> Any[8532]

    pack(sql, Dict("gender" => 8532))
    #-> Any[8532]

If the dialect does not support numbered parameters, `pack()` may need to
duplicate parameter values.

    sql = render(c, dialect = :mysql)

    print(sql)
    #=>
    SELECT "person_id"
    FROM "person"
    WHERE (("gender_concept_id" = ?) OR ("gender_source_concept_id" = ?))
    =#

    pack(sql, (gender = 8532,))
    #-> Any[8532, 8532]


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


## Aggregate Functions

Aggregate SQL functions have a specialized `AGG()` constructor.

    c = AGG("COUNT", OP("*"))
    #-> AGG("COUNT", …)

    display(c)
    #-> AGG("COUNT", OP("*"))

    print(render(c))
    #-> COUNT(*)

Aggregate functions accept the `DISTINCT` modifier.

    c = AGG("COUNT", distinct = true, :year_of_birth)

    display(c)
    #-> AGG("COUNT", distinct = true, ID(:year_of_birth))

    print(render(c))
    #-> COUNT(DISTINCT "year_of_birth")

An aggregate function may have a `FILTER` modifier.

    c = AGG("COUNT", OP("*"), filter = OP(">", :year_of_birth, 1970))

    display(c)
    #-> AGG("COUNT", OP("*"), filter = OP(">", ID(:year_of_birth), LIT(1970)))

    print(render(c))
    #-> (COUNT(*) FILTER (WHERE ("year_of_birth" > 1970)))

A window function can be created by adding an `OVER` modifier.

    c = PARTITION(:year_of_birth, order_by = [:month_of_birth, :day_of_birth]) |>
        AGG("ROW_NUMBER")

    display(c)
    #=>
    AGG("ROW_NUMBER",
        over = PARTITION(ID(:year_of_birth),
                         order_by = [ID(:month_of_birth), ID(:day_of_birth)]))
    =#

    print(render(c))
    #-> (ROW_NUMBER() OVER (PARTITION BY "year_of_birth" ORDER BY "month_of_birth", "day_of_birth"))

    c = AGG("ROW_NUMBER", over = :w)

    print(render(c))
    #-> (ROW_NUMBER() OVER ("w"))

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


## `CASE` Expression

A `CASE` expression is created with `CASE()` constructor.

    c = CASE(OP("<", :year_of_birth, 1970), "boomer")
    #-> CASE(…)

    display(c)
    #-> CASE(OP("<", ID(:year_of_birth), LIT(1970)), LIT("boomer"))

    print(render(c))
    #-> (CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' END)

The arguments of `CASE` form an interleaving sequence of conditions and the
corresponding values.  When `CASE` has an odd number of arguments, the last
argument provides the default value.

    c = CASE(OP("<", :year_of_birth, 1970), "boomer", "millenial")

    print(render(c))
    #-> (CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' ELSE 'millenial' END)

An invalid `CASE` expression can be constructed.

    c = CASE(args = [])
    #-> CASE(args = [])


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
    SELECT "person_id"
    FROM "person"
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
    SELECT "person_id"
    FROM "person"
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
    SELECT "person_id"
    FROM "person"
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

    c = FROM(:person) |> LIMIT(10, with_ties = true) |> SELECT(:person_id)

    display(c)
    #-> ID(:person) |> FROM() |> LIMIT(10, with_ties = true) |> SELECT(ID(:person_id))

    print(render(c))
    #=>
    SELECT "person_id"
    FROM "person"
    FETCH FIRST 10 ROWS WITH TIES
    =#


## `JOIN` Clause

A `JOIN` clause is created with `JOIN()` constructor.

    c = FROM(:p => :person) |>
        JOIN(:l => :location, OP("=", (:p, :location_id), (:l, :location_id)), left = true)
    #-> (…) |> JOIN(…)

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:location) |> AS(:l),
         OP("=", ID(:p) |> ID(:location_id), ID(:l) |> ID(:location_id)),
         left = true)
    =#

    print(render(c |> SELECT((:p, :person_id), (:l, :state))))
    #=>
    SELECT "p"."person_id", "l"."state"
    FROM "person" AS "p"
    LEFT JOIN "location" AS "l" ON ("p"."location_id" = "l"."location_id")
    =#

Different types of `JOIN` are supported.

    c = FROM(:p => :person) |>
        JOIN(:op => :observation_period,
             on = OP("=", (:p, :person_id), (:op, :person_id)))

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:observation_period) |> AS(:op),
         OP("=", ID(:p) |> ID(:person_id), ID(:op) |> ID(:person_id)))
    =#

    print(render(c |> SELECT((:p, :person_id), (:op, :observation_period_start_date))))
    #=>
    SELECT "p"."person_id", "op"."observation_period_start_date"
    FROM "person" AS "p"
    JOIN "observation_period" AS "op" ON ("p"."person_id" = "op"."person_id")
    =#

    c = FROM(:l => :location) |>
        JOIN(:cs => :care_site,
             on = OP("=", (:l, :location_id), (:cs, :location_id)),
             right = true)

    display(c)
    #=>
    ID(:location) |>
    AS(:l) |>
    FROM() |>
    JOIN(ID(:care_site) |> AS(:cs),
         OP("=", ID(:l) |> ID(:location_id), ID(:cs) |> ID(:location_id)),
         right = true)
    =#

    print(render(c |> SELECT((:cs, :care_site_name), (:l, :state))))
    #=>
    SELECT "cs"."care_site_name", "l"."state"
    FROM "location" AS "l"
    RIGHT JOIN "care_site" AS "cs" ON ("l"."location_id" = "cs"."location_id")
    =#

    c = FROM(:p => :person) |>
        JOIN(:pr => :provider,
             on = OP("=", (:p, :provider_id), (:pr, :provider_id)),
             left = true,
             right = true)

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:provider) |> AS(:pr),
         OP("=", ID(:p) |> ID(:provider_id), ID(:pr) |> ID(:provider_id)),
         left = true,
         right = true)
    =#

    print(render(c |> SELECT((:p, :person_id), (:pr, :npi))))
    #=>
    SELECT "p"."person_id", "pr"."npi"
    FROM "person" AS "p"
    FULL JOIN "provider" AS "pr" ON ("p"."provider_id" = "pr"."provider_id")
    =#

To render a `CROSS JOIN`, set the join condition to `true`.

    c = FROM(:p1 => :person) |>
        JOIN(:p2 => :person,
             on = true)

    print(render(c |> SELECT((:p1, :person_id), (:p2, :person_id))))
    #=>
    SELECT "p1"."person_id", "p2"."person_id"
    FROM "person" AS "p1"
    CROSS JOIN "person" AS "p2"
    =#

A `JOIN LATERAL` clause can be created.

    c = FROM(:p => :person) |>
        JOIN(:vo => FROM(:vo => :visit_occurrence) |>
                    WHERE(OP("=", (:p, :person_id), (:vo, :person_id))) |>
                    # TODO: add ORDER BY and LIMIT when they are implemented
                    SELECT((:vo, :visit_start_date)),
             on = true,
             lateral = true)

    display(c)
    #=>
    ID(:person) |>
    AS(:p) |>
    FROM() |>
    JOIN(ID(:visit_occurrence) |>
         AS(:vo) |>
         FROM() |>
         WHERE(OP("=", ID(:p) |> ID(:person_id), ID(:vo) |> ID(:person_id))) |>
         SELECT(ID(:vo) |> ID(:visit_start_date)) |>
         AS(:vo),
         LIT(true),
         lateral = true)
    =#

    print(render(c |> SELECT((:p, :person_id), (:vo, :visit_start_date))))
    #=>
    SELECT "p"."person_id", "vo"."visit_start_date"
    FROM "person" AS "p"
    CROSS JOIN LATERAL (
      SELECT "vo"."visit_start_date"
      FROM "visit_occurrence" AS "vo"
      WHERE ("p"."person_id" = "vo"."person_id")
    ) AS "vo"
    =#


## `GROUP` Clause

A `GROUP BY` clause is created with `GROUP` constructor.

    c = FROM(:person) |> GROUP(:year_of_birth)
    #-> (…) |> GROUP(…)

    display(c)
    #-> ID(:person) |> FROM() |> GROUP(ID(:year_of_birth))

    print(render(c |> SELECT(:year_of_birth, AGG("COUNT", OP("*")))))
    #=>
    SELECT "year_of_birth", COUNT(*)
    FROM "person"
    GROUP BY "year_of_birth"
    =#

A `GROUP` constructor accepts an empty partition list, in which case, it is not
rendered.

    c = FROM(:person) |> GROUP()
    #-> (…) |> GROUP()

    print(render(c |> SELECT(AGG("COUNT", OP("*")))))
    #=>
    SELECT COUNT(*)
    FROM "person"
    =#


## `HAVING` Clause

A `HAVING` clause is created with `HAVING()` constructor.

    c = FROM(:person) |>
        GROUP(:year_of_birth) |>
        HAVING(OP(">", AGG("COUNT", OP("*")), 10))
    #-> (…) |> HAVING(…)

    display(c)
    #=>
    ID(:person) |>
    FROM() |>
    GROUP(ID(:year_of_birth)) |>
    HAVING(OP(">", AGG("COUNT", OP("*")), LIT(10)))
    =#

    print(render(c |> SELECT(:person_id)))
    #=>
    SELECT "person_id"
    FROM "person"
    GROUP BY "year_of_birth"
    HAVING (COUNT(*) > 10)
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
    SELECT "person_id", "measurement_date" AS "date"
    FROM "measurement"
    UNION ALL
    SELECT "person_id", "observation_date" AS "date"
    FROM "observation"
    =#

A `UNION` clause with no subqueries can be created explicitly.

    UNION(list = [])
    #-> UNION(list = [])

Rendering a nested `UNION` clause adds parentheses around it.

    c = FROM(:measurement) |>
        SELECT(:person_id, :date => :measurement_date) |>
        UNION(all = true,
              FROM(:observation) |>
              SELECT(:person_id, :date => :observation_date)) |>
        FROM() |>
        AS(:union) |>
        WHERE(OP(">", ID(:date), Date(2000))) |>
        SELECT(ID(:person_id))

    print(render(c))
    #=>
    SELECT "person_id"
    FROM (
      SELECT "person_id", "measurement_date" AS "date"
      FROM "measurement"
      UNION ALL
      SELECT "person_id", "observation_date" AS "date"
      FROM "observation"
    ) AS "union"
    WHERE ("date" > '2000-01-01')
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
    SELECT (ROW_NUMBER() OVER ("w1")), (ROW_NUMBER() OVER ("w2"))
    FROM "person"
    WINDOW "w1" AS (PARTITION BY "gender_concept_id"), "w2" AS ("w1" PARTITION BY "year_of_birth" ORDER BY "month_of_birth", "day_of_birth")
    =#

The `WINDOW()` constructor accepts an empty list of partitions, in which case,
it is not rendered.

    c = FROM(:person) |>
        WINDOW(list = [])

    display(c)
    #-> ID(:person) |> FROM() |> WINDOW(list = [])

    print(render(c |> SELECT(AGG("ROW_NUMBER", over = PARTITION()))))
    #=>
    SELECT (ROW_NUMBER() OVER ())
    FROM "person"
    =#

