# Examples

```@meta
CurrentModule = FunSQL
```


## Establishing a Database Connection

We use FunSQL to assemble SQL queries.  To actually run these queries, we need
a regular database library such as
[SQLite.jl](https://github.com/JuliaDatabases/SQLite.jl),
[LibPQ.jl](https://github.com/invenia/LibPQ.jl),
[MySQL.jl](https://github.com/JuliaDatabases/MySQL.jl), or
[ODBC.jl](https://github.com/JuliaDatabases/ODBC.jl).

In the following examples, we use a SQLite database containing a tiny sample
of the [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).
See the [Usage Guide](@ref Database-Schema) for the description of the database
schema.

*Download the database file.*

```julia
const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"
const DB = download(URL)
```

*Download the database file as an [artifact](../Artifacts.toml).*

    using Pkg.Artifacts, LazyArtifacts

    const DB = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")
    #-> ⋮

*Create a SQLite connection object.*

    using SQLite

    const conn = SQLite.DB(DB)


## Importing FunSQL

FunSQL does not export any symbols by default.  The following statement imports
all available query constructors, a [`SQLTable`](@ref) constructor, and the
function [`render`](@ref).

    using FunSQL:
        Agg, Append, As, Asc, Bind, Define, Desc, Fun, From, Get, Group,
        Highlight, Join, LeftJoin, Limit, Lit, Order, Partition, SQLTable,
        Select, Sort, Var, Where, render


## Database Introspection (SQLite)

For each database table referenced in a query, we need to create a
[`SQLTable`](@ref) object encapsulating the name of the table and the list of
the table columns.

    SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id])

Instead of creating `SQLTable` objects manually, we could create them
automatically by extracting the information about the available tables from the
database itself.  For SQLite, this could be done as follows.

    using Tables

    const introspect_sqlite_sql = """
        SELECT NULL AS schema, sm.name, pti.name AS column
        FROM sqlite_master sm, pragma_table_info(sm.name) pti
        WHERE sm.type IN ('table', 'view') AND sm.name NOT LIKE 'sqlite_%'
        ORDER BY sm.name
        """

    introspect_sqlite(conn) =
        DBInterface.execute(conn, introspect_sqlite_sql) |>
        make_tables

    function make_tables(res)
        tables = SQLTable[]
        schema = name = nothing
        columns = Symbol[]
        for (s, n, c) in Tables.rows(res)
            s = s !== missing ? Symbol(s) : nothing
            n = Symbol(n)
            c = Symbol(c)
            if s === schema && n === name
                push!(columns, c)
            else
                if !isempty(columns)
                    t = SQLTable(schema = schema, name = name, columns = columns)
                    push!(tables, t)
                end
                schema = s
                name = n
                columns = [c]
            end
        end
        if !isempty(columns)
            t = SQLTable(schema = schema, name = name, columns = columns)
            push!(tables, t)
        end
        return tables
    end

    const tables = introspect_sqlite(conn)

The vector `tables` contains all the tables available in the database.

    display(tables)
    #=>
    44-element Vector{SQLTable}:
     SQLTable(:attribute_definition, …)
     SQLTable(:care_site, …)
     SQLTable(:cdm_source, …)
     SQLTable(:cohort, …)
     SQLTable(:cohort_ace, …)
     SQLTable(:cohort_all, …)
     SQLTable(:cohort_ami, …)
     SQLTable(:cohort_ang, …)
     SQLTable(:cohort_attribute, …)
     SQLTable(:cohort_definition, …)
     ⋮
     SQLTable(:procedure_cost, …)
     SQLTable(:procedure_occurrence, …)
     SQLTable(:provider, …)
     SQLTable(:relationship, …)
     SQLTable(:source_to_concept_map, …)
     SQLTable(:specimen, …)
     SQLTable(:visit_cost, …)
     SQLTable(:visit_occurrence, …)
     SQLTable(:vocabulary, …)
    =#

It is convenient to add the `SQLTable` objects to the global scope.

    for t in tables
        @eval const $(t.name) = $t
    end

    display(person)
    #=>
    SQLTable(:person,
             columns = [:person_id,
                        :gender_concept_id,
                        :year_of_birth,
                        :month_of_birth,
                        :day_of_birth,
                        :time_of_birth,
                        :race_concept_id,
                        :ethnicity_concept_id,
                        :location_id,
                        :provider_id,
                        :care_site_id,
                        :person_source_value,
                        :gender_source_value,
                        :gender_source_concept_id,
                        :race_source_value,
                        :race_source_concept_id,
                        :ethnicity_source_value,
                        :ethnicity_source_concept_id])
    =#

Alternatively, we could encapsulate all `SQLTable` objects in a `NamedTuple`.

    const db = NamedTuple([t.name => t for t in tables])

    display(db.person)
    #=>
    SQLTable(:person,
             columns = [:person_id,
                        :gender_concept_id,
                        :year_of_birth,
                        :month_of_birth,
                        :day_of_birth,
                        :time_of_birth,
                        :race_concept_id,
                        :ethnicity_concept_id,
                        :location_id,
                        :provider_id,
                        :care_site_id,
                        :person_source_value,
                        :gender_source_value,
                        :gender_source_concept_id,
                        :race_source_value,
                        :race_source_concept_id,
                        :ethnicity_source_value,
                        :ethnicity_source_concept_id])
    =#


## Database Introspection (PostgreSQL)

The following code generates `SQLTable` objects for a PostgreSQL database.  See
the section [Database Introspection (SQLite)](@ref) for the definition of the
`make_tables()` function and instructions on how to bring the generated
`SQLTable` objects into the global scope.

```julia
const introspect_postgresql_sql = """
    SELECT n.nspname AS schema, c.relname AS name, a.attname AS column
    FROM pg_catalog.pg_namespace AS n
    JOIN pg_catalog.pg_class AS c ON (n.oid = c.relnamespace)
    JOIN pg_catalog.pg_attribute AS a ON (c.oid = a.attrelid)
    WHERE n.nspname = \$1 AND
          c.relkind IN ('r', 'v') AND
          HAS_TABLE_PRIVILEGE(c.oid, 'SELECT') AND
          a.attnum > 0 AND
          NOT a.attisdropped
    ORDER BY n.nspname, c.relname, a.attnum
    """

introspect_postgresql(conn, schema = :public) =
    execute(conn, introspect_postgresql_sql, (String(schema),)) |>
    make_tables
```

Alternatively, we could generate the introspection query using FunSQL.

```julia
const pg_namespace =
    SQLTable(schema = :pg_catalog,
             name = :pg_namespace,
             columns = [:oid, :nspname])
const pg_class =
    SQLTable(schema = :pg_catalog,
             name = :pg_class,
             columns = [:oid, :relname, :relnamespace, :relkind])
const pg_attribute =
    SQLTable(schema = :pg_catalog,
             name = :pg_attribute,
             columns = [:attrelid, :attname, :attnum, :attisdropped])

const IntrospectPostgreSQL =
    From(pg_class) |>
    Where(Fun.in(Get.relkind, "r", "v")) |>
    Where(Fun.has_table_privilege(Get.oid, "SELECT")) |>
    Join(From(pg_namespace) |>
         Where(Get.nspname .== Var.schema) |>
         As(:nsp),
         on = Get.relnamespace .== Get.nsp.oid) |>
    Join(From(pg_attribute) |>
         Where(Fun.and(Get.attnum .> 0, Fun.not(Get.attisdropped))) |>
         As(:att),
         on = Get.oid .== Get.att.attrelid) |>
    Order(Get.nsp.nspname, Get.relname, Get.att.attnum) |>
    Select(Get.nsp.nspname, Get.relname, Get.att.attname)

const introspect_postgresql_sql =
    render(IntrospectPostgreSQL, dialect = :postgresql)
```


## Database Introspection (MySQL)

The following code generates `SQLTable` objects for a MySQL database.  See the
section [Database Introspection (SQLite)](@ref) for the definition of the
`make_tables()` function and instructions on how to bring the generated
`SQLTable` objects into the global scope.

```julia
const introspect_mysql_sql = """
    SELECT table_schema AS `schema`, table_name AS `name`, column_name AS `column`
    FROM information_schema.columns
    WHERE table_schema = COALESCE(?, DATABASE())
    ORDER BY table_schema, table_name, ordinal_position
    """

introspect_mysql(conn, schema = nothing) =
    DBInterface.execute(
        DBInterface.prepare(conn, introspect_mysql_sql),
        (schema !== nothing ? String(schema) : missing,)) |>
    make_tables
```

Alternatively, we could generate the introspection query using FunSQL.

```julia
const information_schema_columns =
    SQLTable(schema = :information_schema,
             name = :columns,
             columns = [:table_schema, :table_name, :column_name, :ordinal_position])

const IntrospectMySQL =
    From(information_schema_columns) |>
    Where(Get.table_schema .== Fun.coalesce(Var.schema, Fun.database())) |>
    Order(Get.table_schema, Get.table_name, Get.ordinal_position) |>
    Select(Get.table_schema, Get.table_name, Get.column_name)

const introspect_mysql_sql =
    render(IntrospectMySQL, dialect = :mysql) |> String
```


## Database Introspection (Microsoft SQL Server)

The following code generates `SQLTable` objects for a Microsoft SQL Server
database.  See the section [Database Introspection (SQLite)](@ref) for the
definition of the `make_tables()` function and instructions on how to bring the
generated `SQLTable` objects into the global scope.

```julia
const introspect_sqlserver_sql = """
    SELECT s.name AS [schema], o.name AS [name], c.name AS [column]
    FROM sys.schemas AS s
    JOIN sys.objects AS o ON (s.schema_id = o.schema_id)
    JOIN sys.columns AS c ON (o.object_id = c.object_id)
    WHERE s.name = ? AND o.type IN ('U', 'V')
    ORDER BY s.name, o.name, c.column_id
    """

introspect_sqlserver(conn, schema = :dbo) =
    DBInterface.execute(conn, introspect_sqlserver_sql, (String(schema),)) |>
    make_tables
```

Alternatively, we could generate the introspection query using FunSQL.

```julia
const sys_schemas =
    SQLTable(schema = :sys, name = :schemas, columns = [:schema_id, :name])
const sys_tables =
    SQLTable(schema = :sys, name = :tables, columns = [:schema_id, :object_id, :name, :type])
const sys_columns =
    SQLTable(schema = :sys, name = :columns, columns = [:object_id, :column_id, :name])

const IntrospectSQLServer =
    From(sys_tables) |>
    Where(Fun.in(Get.type, "U", "V")) |>
    Join(From(sys_schemas) |>
         Where(Get.name .== Var.schema) |>
         As(:schema),
         on = Get.schema_id .== Get.schema.schema_id) |>
    Join(From(sys_columns) |>
         As(:column),
         on = Get.object_id .== Get.column.object_id) |>
    Order(Get.schema.name, Get.name, Get.column.column_id) |>
    Select(:schema => Get.schema.name, Get.name, :column => Get.column.name)

const introspect_sqlserver_sql =
    render(IntrospectSQLServer, dialect = :sqlserver)
```


## Database Introspection (Amazon RedShift)

See [Database Introspection (PostgreSQL)](@ref).


## `SELECT * FROM table`

FunSQL does not require that a query object contains `Select`, so a minimal
FunSQL query consists of a single [`From`](@ref) node.

*Show all patient records.*

    q = From(person)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_1"."person_id", …, "person_1"."ethnicity_source_concept_id"
    FROM "person" AS "person_1"
    =#

    res = DBInterface.execute(conn, sql)

To display the output of a query, it is convenient to use the
[DataFrame](https://github.com/JuliaData/DataFrames.jl) interface.

    using DataFrames

    DataFrame(res)
    #=>
    10×18 DataFrame
     Row │ person_id  gender_concept_id  year_of_birth  month_of_birth  day_of_bir ⋯
         │ Int64      Int64              Int64          Int64           Int64      ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │      1780               8532           1940               2             ⋯
       2 │     30091               8532           1932               8
       3 │     37455               8532           1913               7
       4 │     42383               8507           1922               2
       5 │     69985               8532           1956               7             ⋯
       6 │     72120               8507           1937              10
       7 │     82328               8532           1957               9
       8 │     95538               8507           1923              11
       9 │    107680               8532           1963              12             ⋯
      10 │    110862               8507           1911               4
                                                                  14 columns omitted
    =#


## `WHERE`, `ORDER`, `LIMIT`

Tabular operations such as [`Where`](@ref), [`Order`](@ref), and
[`Limit`](@ref) are available in FunSQL.  Unlike SQL, FunSQL lets you apply
them in any order.

*Show the top 3 oldest male patients.*

    q = From(person) |>
        Where(Get.gender_concept_id .== 8507) |>
        Order(Get.year_of_birth) |>
        Limit(3)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_1"."person_id", …, "person_1"."ethnicity_source_concept_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."gender_concept_id" = 8507)
    ORDER BY "person_1"."year_of_birth"
    LIMIT 3
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    3×18 DataFrame
     Row │ person_id  gender_concept_id  year_of_birth  month_of_birth  day_of_bir ⋯
         │ Int64      Int64              Int64          Int64           Int64      ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │    110862               8507           1911               4             ⋯
       2 │     42383               8507           1922               2
       3 │     95538               8507           1923              11
                                                                  14 columns omitted
    =#

*Show all males among the top 3 oldest patients.*

    q = From(person) |>
        Order(Get.year_of_birth) |>
        Limit(3) |>
        Where(Get.gender_concept_id .== 8507)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_2"."person_id", …, "person_2"."ethnicity_source_concept_id"
    FROM (
      SELECT "person_1"."person_id", …, "person_1"."ethnicity_source_concept_id"
      FROM "person" AS "person_1"
      ORDER BY "person_1"."year_of_birth"
      LIMIT 3
    ) AS "person_2"
    WHERE ("person_2"."gender_concept_id" = 8507)
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    2×18 DataFrame
     Row │ person_id  gender_concept_id  year_of_birth  month_of_birth  day_of_bir ⋯
         │ Int64      Int64              Int64          Int64           Int64      ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │    110862               8507           1911               4             ⋯
       2 │     42383               8507           1922               2
                                                                  14 columns omitted
    =#


## `SELECT COUNT(*) FROM table`

To apply an aggregate function to the dataset as a whole, we use a
[`Group`](@ref) node without arguments.

*Show the number of patient records.*

    q = From(person) |>
        Group() |>
        Select(Agg.count())

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT COUNT(*) AS "count"
    FROM "person" AS "person_1"
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    1×1 DataFrame
     Row │ count
         │ Int64
    ─────┼───────
       1 │    10
    =#


## `SELECT DISTINCT`

If we use a [`Group`](@ref) node, but do not apply any aggregate functions,
FunSQL will render it as a `SELECT DISTINCT` clause.

*Show all US states present in the location records.*

    q = From(location) |>
        Group(Get.state)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT DISTINCT "location_1"."state"
    FROM "location" AS "location_1"
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    10×1 DataFrame
     Row │ state
         │ String
    ─────┼────────
       1 │ MI
       2 │ WA
       3 │ FL
       4 │ MD
       5 │ NY
       6 │ MS
       7 │ CO
       8 │ GA
       9 │ MA
      10 │ IL
    =#


## Filtering Output Columns

Either broadcasting or vector comprehension could be used to filter the list of
output columns.

*Filter out all "source" columns from patient records.*

    is_not_source_column(c::Symbol) =
        !contains(String(c), "source")

    q = From(person) |>
        Select(Get.(filter(is_not_source_column, person.columns))...)

    # q = From(person) |>
    #     Select(list = [Get(c) for c in person.columns if is_not_source_column(c)])

    display(q)
    #=>
    let person = SQLTable(:person, …),
        q1 = From(person),
        q2 = q1 |>
             Select(Get.person_id,
                    Get.gender_concept_id,
                    Get.year_of_birth,
                    Get.month_of_birth,
                    Get.day_of_birth,
                    Get.time_of_birth,
                    Get.race_concept_id,
                    Get.ethnicity_concept_id,
                    Get.location_id,
                    Get.provider_id,
                    Get.care_site_id)
        q2
    end
    =#

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_1"."person_id", …, "person_1"."care_site_id"
    FROM "person" AS "person_1"
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    10×11 DataFrame
     Row │ person_id  gender_concept_id  year_of_birth  month_of_birth  day_of_bir ⋯
         │ Int64      Int64              Int64          Int64           Int64      ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │      1780               8532           1940               2             ⋯
       2 │     30091               8532           1932               8
       3 │     37455               8532           1913               7
       4 │     42383               8507           1922               2
       5 │     69985               8532           1956               7             ⋯
       6 │     72120               8507           1937              10
       7 │     82328               8532           1957               9
       8 │     95538               8507           1923              11
       9 │    107680               8532           1963              12             ⋯
      10 │    110862               8507           1911               4
                                                                   7 columns omitted
    =#


## Output Columns of a Join

[`As`](@ref) is often used to disambiguate the columns of the two input
branches of the [`Join`](@ref) node.  By default, columns fenced by `As` are
not present in the output.

    q = From(person) |>
        Join(From(visit_occurrence) |> As(:visit),
             on = Get.person_id .== Get.visit.person_id)

    print(render(q, dialect = :sqlite))
    #=>
    SELECT "person_1"."person_id", …, "person_1"."ethnicity_source_concept_id"
    FROM "person" AS "person_1"
    JOIN "visit_occurrence" AS "visit_occurrence_1" ON ("person_1"."person_id" = "visit_occurrence_1"."person_id")
    =#

    q′ = From(person) |> As(:person) |>
         Join(From(visit_occurrence),
              on = Get.person.person_id .== Get.person_id)

    print(render(q′, dialect = :sqlite))
    #=>
    SELECT "visit_occurrence_1"."visit_occurrence_id", …, "visit_occurrence_1"."visit_source_concept_id"
    FROM "person" AS "person_1"
    JOIN "visit_occurrence" AS "visit_occurrence_1" ON ("person_1"."person_id" = "visit_occurrence_1"."person_id")
    =#

We could use a [`Select`](@ref) node to output the columns of both branches,
however we must ensure that all column names are unique.

    q = q |>
        Select(Get.(person.columns)...,
               Get.(visit_occurrence.columns, over = Get.visit)...)
    #=>
    ERROR: FunSQL.DuplicateLabelError: person_id is used more than once in:
    ⋮
    =#

    q = q |>
        Select(Get.(person.columns)...,
               Get.(filter(!in(person.columns), visit_occurrence.columns),
                    over = Get.visit)...)

    print(render(q, dialect = :sqlite))
    #=>
    SELECT "person_1"."person_id", …, "visit_occurrence_1"."visit_source_concept_id"
    FROM "person" AS "person_1"
    JOIN "visit_occurrence" AS "visit_occurrence_1" ON ("person_1"."person_id" = "visit_occurrence_1"."person_id")
    =#


## Assembling Queries Incrementally

It is often convenient to build a query incrementally, one component at a time.
This allows us to validate individual components, inspect their output, and
possibly reuse them in other queries.  Note that FunSQL allows to encapsulate
not just intermediate datasets, but also dataset operations such as
`FilterByGap()`.

*Find all occurrences of myocardial infarction that was diagnosed during an
inpatient visit.  Filter out repeating occurrences by requiring a 180-day gap
between consecutive events.*

    using Dates

    ConceptByName(name) =
        From(concept) |>
        Where(Fun.like(Get.concept_name, "%$(name)%"))

    MyocardialInfarctionConcept() =
        ConceptByName("myocardial infarction")

    MyocardialInfarctionOccurrence() =
        From(condition_occurrence) |>
        Join(:concept => MyocardialInfarctionConcept(),
             on = Get.condition_concept_id .== Get.concept.concept_id)

    InpatientVisitConcept() =
        ConceptByName("inpatient")

    InpatientVisitOccurrence() =
        From(visit_occurrence) |>
        Join(:concept => InpatientVisitConcept(),
             on = Get.visit_concept_id .== Get.concept.concept_id)

    CorrelatedInpatientVisit(person_id, date) =
        InpatientVisitOccurrence() |>
        Where(Fun.and(Get.person_id .== Var.person_id,
                      Fun.between(Var.date, Get.visit_start_date, Get.visit_end_date))) |>
        Bind(:person_id => person_id,
             :date => date)

    MyocardialInfarctionDuringInpatientVisit() =
        MyocardialInfarctionOccurrence() |>
        Where(Fun.exists(CorrelatedInpatientVisit(Get.person_id, Get.condition_start_date)))

    FilterByGap(date, gap) =
        Partition(Get.person_id, order_by = [date]) |>
        Define(:boundary => Agg.lag(Fun.date(date, gap))) |>
        Where(Fun.or(Fun."is null"(Get.boundary),
                     Get.boundary .< date))

    FilteredMyocardialInfarctionDuringInpatientVisit() =
        MyocardialInfarctionDuringInpatientVisit() |>
        FilterByGap(Get.condition_start_date, Day(180))

    q = FilteredMyocardialInfarctionDuringInpatientVisit() |>
        Select(Get.person_id, Get.condition_start_date)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "condition_occurrence_2"."person_id", "condition_occurrence_2"."condition_start_date"
    FROM (
      SELECT "condition_occurrence_1"."person_id", "condition_occurrence_1"."condition_start_date", (LAG(DATE("condition_occurrence_1"."condition_start_date", '180 days')) OVER (PARTITION BY "condition_occurrence_1"."person_id" ORDER BY "condition_occurrence_1"."condition_start_date")) AS "boundary"
      FROM "condition_occurrence" AS "condition_occurrence_1"
      JOIN (
        SELECT "concept_1"."concept_id"
        FROM "concept" AS "concept_1"
        WHERE ("concept_1"."concept_name" LIKE '%myocardial infarction%')
      ) AS "concept_2" ON ("condition_occurrence_1"."condition_concept_id" = "concept_2"."concept_id")
      WHERE (EXISTS (
        SELECT NULL
        FROM "visit_occurrence" AS "visit_occurrence_1"
        JOIN (
          SELECT "concept_3"."concept_id"
          FROM "concept" AS "concept_3"
          WHERE ("concept_3"."concept_name" LIKE '%inpatient%')
        ) AS "concept_4" ON ("visit_occurrence_1"."visit_concept_id" = "concept_4"."concept_id")
        WHERE (("visit_occurrence_1"."person_id" = "condition_occurrence_1"."person_id") AND ("condition_occurrence_1"."condition_start_date" BETWEEN "visit_occurrence_1"."visit_start_date" AND "visit_occurrence_1"."visit_end_date"))
      ))
    ) AS "condition_occurrence_2"
    WHERE (("condition_occurrence_2"."boundary" IS NULL) OR ("condition_occurrence_2"."boundary" < "condition_occurrence_2"."condition_start_date"))
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    1×2 DataFrame
     Row │ person_id  condition_start_date
         │ Int64      String
    ─────┼─────────────────────────────────
       1 │      1780  2008-04-10
    =#


## Merging Overlapping Intervals

Merging overlapping intervals into a single encompassing period could be done
in three steps:

1. Tag the intervals that start a new period.
2. Enumerate the periods.
3. Group the intervals by the period number.

FunSQL lets us encapsulate and reuse this rather complex sequence of
transformations.

*Merge overlapping visits.*

    MergeOverlappingIntervals(start_date, end_date) =
        Partition(Get.person_id,
                  order_by = [start_date],
                  frame = (mode = :rows, start = -Inf, finish = -1)) |>
        Define(:new => Fun.case(start_date .<= Agg.max(end_date), 0, 1)) |>
        Partition(Get.person_id,
                  order_by = [start_date, .- Get.new],
                  frame = :rows) |>
        Define(:period => Agg.sum(Get.new)) |>
        Group(Get.person_id, Get.period) |>
        Define(:start_date => Agg.min(start_date),
               :end_date => Agg.max(end_date))

    q = From(visit_occurrence) |>
        MergeOverlappingIntervals(Get.visit_start_date, Get.visit_end_date) |>
        Select(Get.person_id, Get.start_date, Get.end_date)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "visit_occurrence_3"."person_id", MIN("visit_occurrence_3"."visit_start_date") AS "start_date", MAX("visit_occurrence_3"."visit_end_date") AS "end_date"
    FROM (
      SELECT "visit_occurrence_2"."person_id", (SUM("visit_occurrence_2"."new") OVER (PARTITION BY "visit_occurrence_2"."person_id" ORDER BY "visit_occurrence_2"."visit_start_date", (- "visit_occurrence_2"."new") ROWS UNBOUNDED PRECEDING)) AS "period", "visit_occurrence_2"."visit_start_date", "visit_occurrence_2"."visit_end_date"
      FROM (
        SELECT "visit_occurrence_1"."person_id", (CASE WHEN ("visit_occurrence_1"."visit_start_date" <= (MAX("visit_occurrence_1"."visit_end_date") OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date" ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING))) THEN 0 ELSE 1 END) AS "new", "visit_occurrence_1"."visit_start_date", "visit_occurrence_1"."visit_end_date"
        FROM "visit_occurrence" AS "visit_occurrence_1"
      ) AS "visit_occurrence_2"
    ) AS "visit_occurrence_3"
    GROUP BY "visit_occurrence_3"."person_id", "visit_occurrence_3"."period"
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    25×3 DataFrame
     Row │ person_id  start_date  end_date
         │ Int64      String      String
    ─────┼───────────────────────────────────
       1 │      1780  2008-04-09  2008-04-13
       2 │      1780  2008-11-22  2008-11-22
       3 │      1780  2009-05-22  2009-05-22
       4 │     30091  2008-11-12  2008-11-12
       5 │     30091  2009-07-30  2009-08-07
       6 │     37455  2008-03-18  2008-03-18
       7 │     37455  2008-10-30  2008-10-30
       8 │     37455  2010-08-12  2010-08-12
      ⋮  │     ⋮          ⋮           ⋮
      19 │     95538  2009-09-02  2009-09-02
      20 │    107680  2009-06-07  2009-06-07
      21 │    107680  2009-07-20  2009-07-30
      22 │    110862  2008-09-07  2008-09-16
      23 │    110862  2009-06-30  2009-06-30
      24 │    110862  2009-09-30  2009-10-01
      25 │    110862  2010-06-07  2010-06-07
                              10 rows omitted
    =#

