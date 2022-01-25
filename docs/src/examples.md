# Examples

```@meta
CurrentModule = FunSQL
```


## Importing FunSQL

FunSQL does not export any symbols by default.  The following statement imports
all available query constructors and the function [`render`](@ref).

    using FunSQL:
        FunSQL, Agg, Append, As, Asc, Bind, Define, Desc, Fun, From, Get,
        Group, Highlight, Iterate, Join, LeftJoin, Limit, Lit, Order,
        Partition, Select, Sort, Var, Where, With, WithExternal, render


## Establishing a database connection

We use FunSQL to assemble SQL queries.  To actually run these queries, we need
a regular database library such as
[SQLite.jl](https://github.com/JuliaDatabases/SQLite.jl),
[LibPQ.jl](https://github.com/invenia/LibPQ.jl),
[MySQL.jl](https://github.com/JuliaDatabases/MySQL.jl), or
[ODBC.jl](https://github.com/JuliaDatabases/ODBC.jl).

In the following examples, we use a SQLite database containing a tiny sample
of the [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).
See the [Usage Guide](@ref Test-Database) for the description of the database
schema.

*Download the database file.*

```julia
const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"
const DATABASE = download(URL)
```

*Download the database file as an [artifact](../Artifacts.toml).*

    using Pkg.Artifacts, LazyArtifacts

    const DATABASE = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")
    #-> ⋮

*Create a connection object.*

    using SQLite

    const conn = DBInterface.connect(FunSQL.DB{SQLite.DB}, DATABASE)


## Database connection with LibPQ.jl

To create a connection object, FunSQL relies on the
[DBInterface.jl](https://github.com/JuliaDatabases/DBInterface.jl) package.
Unfortunately [LibPQ.jl](https://github.com/invenia/LibPQ.jl), the PostgreSQL
client library, does not support DBInterface.  To make `DBInterface.connect`
work, we need to manually bridge LibPQ and DBInterface.

```julia
using LibPQ
using DBInterface

DBInterface.connect(::Type{LibPQ.Connection}, args...; kws...) =
    LibPQ.Connection(args...; kws...)

DBInterface.prepare(conn::LibPQ.Connection, args...; kws...) =
    LibPQ.prepare(conn, args...; kws...)

DBInterface.execute(conn::Union{LibPQ.Connection, LibPQ.Statement}, args...; kws...) =
    LibPQ.execute(conn, args...; kws...)
```

Now we can create a FunSQL connection using `DBInterface.connect`.

```julia
const conn = DBInterface.connect(FunSQL.DB{LibPQ.Connection}, …)
```


## `SELECT * FROM table`

FunSQL does not require that a query object contains `Select`, so a minimal
FunSQL query consists of a single [`From`](@ref) node.

*Show all patient records.*

    q = From(:person)

We use the function [`render`](@ref) to serialize the query node as a SQL
statement.

    sql = render(conn, q)

    print(sql)
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."ethnicity_source_concept_id"
    FROM "person" AS "person_1"
    =#

This query could be executed with `DBInterface.execute`.

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

We could also directly apply `DBInterface.execute` to the query node in order
to render and immediately execute it.

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    10×18 DataFrame
    ⋮
    =#


## `WHERE`, `ORDER`, `LIMIT`

Tabular operations such as [`Where`](@ref), [`Order`](@ref), and
[`Limit`](@ref) are available in FunSQL.  Unlike SQL, FunSQL lets you apply
them in any order.

*Show the top 3 oldest male patients.*

    q = From(:person) |>
        Where(Get.gender_concept_id .== 8507) |>
        Order(Get.year_of_birth) |>
        Limit(3)

    render(conn, q) |> print
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."ethnicity_source_concept_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."gender_concept_id" = 8507)
    ORDER BY "person_1"."year_of_birth"
    LIMIT 3
    =#

    DBInterface.execute(conn, q) |> DataFrame
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

    q = From(:person) |>
        Order(Get.year_of_birth) |>
        Limit(3) |>
        Where(Get.gender_concept_id .== 8507)

    render(conn, q) |> print
    #=>
    SELECT
      "person_2"."person_id",
      ⋮
      "person_2"."ethnicity_source_concept_id"
    FROM (
      SELECT
        "person_1"."person_id",
        ⋮
        "person_1"."ethnicity_source_concept_id"
      FROM "person" AS "person_1"
      ORDER BY "person_1"."year_of_birth"
      LIMIT 3
    ) AS "person_2"
    WHERE ("person_2"."gender_concept_id" = 8507)
    =#

    DBInterface.execute(conn, q) |> DataFrame
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

To calculate an aggregate value for the whole dataset, we apply a
[`Group`](@ref) node without arguments.

*Show the number of patient records.*

    q = From(:person) |>
        Group() |>
        Select(Agg.count())

    render(conn, q) |> print
    #=>
    SELECT COUNT(*) AS "count"
    FROM "person" AS "person_1"
    =#

    DBInterface.execute(conn, q) |> DataFrame
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

    q = From(:location) |>
        Group(Get.state)

    render(conn, q) |> print
    #=>
    SELECT DISTINCT "location_1"."state"
    FROM "location" AS "location_1"
    =#

    DBInterface.execute(conn, q) |> DataFrame
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


## Filtering output columns

By default, the [`From`](@ref) node outputs all columns of a table, but we
could restrict or change the list of output columns using [`Select`](@ref).
Typically, we would directly pass the definitions of output columns as
individual arguments of `Select`, but occasionally it is convenient to generate
the definitions programmatically.

*Filter out all "source" columns from patient records.*

    const person_table = conn.catalog[:person]

    is_not_source_column(c::Symbol) =
        !contains(String(c), "source")

    q = From(:person) |>
        Select(Get.(filter(is_not_source_column, person_table.columns))...)

    # q = From(:person) |>
    #     Select(args = [Get(c) for c in person_table.columns if is_not_source_column(c)])

    display(q)
    #=>
    let q1 = From(:person),
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

    render(conn, q) |> print
    #=>
    SELECT
      "person_1"."person_id",
      "person_1"."gender_concept_id",
      "person_1"."year_of_birth",
      "person_1"."month_of_birth",
      "person_1"."day_of_birth",
      "person_1"."time_of_birth",
      "person_1"."race_concept_id",
      "person_1"."ethnicity_concept_id",
      "person_1"."location_id",
      "person_1"."provider_id",
      "person_1"."care_site_id"
    FROM "person" AS "person_1"
    =#

    DBInterface.execute(conn, q) |> DataFrame
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

## Output columns of a `Join`

[`As`](@ref) is often used to disambiguate the columns of the two input
branches of the [`Join`](@ref) node.  By default, columns fenced by `As` are
not present in the output.

    q = From(:person) |>
        Join(From(:visit_occurrence) |> As(:visit),
             on = Get.person_id .== Get.visit.person_id)

    render(conn, q) |> print
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."ethnicity_source_concept_id"
    FROM "person" AS "person_1"
    JOIN "visit_occurrence" AS "visit_occurrence_1" ON ("person_1"."person_id" = "visit_occurrence_1"."person_id")
    =#

    q′ = From(:person) |> As(:person) |>
         Join(From(:visit_occurrence),
              on = Get.person.person_id .== Get.person_id)

    render(conn, q′) |> print
    #=>
    SELECT
      "visit_occurrence_1"."visit_occurrence_id",
      ⋮
      "visit_occurrence_1"."visit_source_concept_id"
    FROM "person" AS "person_1"
    JOIN "visit_occurrence" AS "visit_occurrence_1" ON ("person_1"."person_id" = "visit_occurrence_1"."person_id")
    =#

We could use a [`Select`](@ref) node to output the columns of both branches,
however we must ensure that all column names are unique.

    const visit_occurrence_table = conn.catalog[:visit_occurrence]

    q = q |>
        Select(Get.(person_table.columns)...,
               Get.(visit_occurrence_table.columns, over = Get.visit)...)
    #=>
    ERROR: FunSQL.DuplicateLabelError: person_id is used more than once in:
    ⋮
    =#

    q = q |>
        Select(Get.(person_table.columns)...,
               Get.(filter(!in(person_table.columns), visit_occurrence_table.columns),
                    over = Get.visit)...)

    render(conn, q) |> print
    #=>
    SELECT
      "person_1"."person_id",
      ⋮
      "person_1"."ethnicity_source_concept_id",
      "visit_occurrence_1"."visit_occurrence_id",
      ⋮
      "visit_occurrence_1"."visit_source_concept_id"
    FROM "person" AS "person_1"
    JOIN "visit_occurrence" AS "visit_occurrence_1" ON ("person_1"."person_id" = "visit_occurrence_1"."person_id")
    =#


## Querying concepts

Medical terms, such as *Inpatient* (visit) or *Myocardial infarction*
(condition), are stored in the table `concept`.  Concepts are typically
identified by the *vocabulary* and the *code* within the vocabulary.  For
example, *Myocardial infarction* has a code *22298006* in the [*SNOMED
CT*](https://en.wikipedia.org/wiki/SNOMED_CT) vocabulary.

Concept may be related to each other.  For example, *Acute myocardial
infarction* **is a** subtype of *Myocardial infarction*.  Relationships between
concepts are stored in the table `concept_relationship` with the column
`relationship_id` specifying the type of the relationship.

Querying healthcare information often starts with identifying the set
of relevant concepts.  For example, a researcher may want to specify
a concept set containing

* *Myocardial infarction* (SNOMED 22298006);
* And all the subtypes;
* But excluding *Acute subendocardial infarction* (SNOMED 70422006).

This suggests us to make a FunSQL-based mini-language for querying concept
sets.  This language will include primitives for fetching concepts by name, or
by vocabulary and code, operations for adding related concepts, and combining
and excluding concept sets.  These operations could be expressed directly in
terms of FunSQL queries.

We start with a primitive for finding a concept by its code in the vocabulary.

    ConceptByCode(vocabulary, code) =
        From(:concept) |>
        Where(Fun.and(Get.vocabulary_id .== vocabulary,
                      Get.concept_code .== code))

    ConceptByCode(vocabulary, codes...) =
        From(:concept) |>
        Where(Fun.and(Get.vocabulary_id .== vocabulary,
                      Fun.in(Get.concept_code, codes...)))

It is convenient to add a shortcut for common vocabularies.

    SNOMED(codes...) =
        ConceptByCode("SNOMED", codes...)

Now we can define

    q = SNOMED("22298006")          # Myocardial infarction

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    1×10 DataFrame
     Row │ concept_id  concept_name           domain_id  vocabulary_id  concept_cl ⋯
         │ Int64       String                 String     String         String     ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │    4329847  Myocardial infarction  Condition  SNOMED         Clinical F ⋯
                                                                   6 columns omitted
    =#

The following composite query pipeline can be applied to a set of concepts to
determine their immediate subtypes.

    ImmediateSubtypes() =
        As(:base) |>
        Join(From(:concept_relationship) |>
             Where(Get.relationship_id .== "Is a") |>
             As(:concept_relationship),
             on = Get.base.concept_id .== Get.concept_relationship.concept_id_2) |>
        Join(From(:concept),
             on = Get.concept_relationship.concept_id_1 .== Get.concept_id)

    q = SNOMED("22298006") |>       # Myocardial infarction
        ImmediateSubtypes()

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    1×10 DataFrame
     Row │ concept_id  concept_name                 domain_id  vocabulary_id  conc ⋯
         │ Int64       String                       String     String         Stri ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │     312327  Acute myocardial infarction  Condition  SNOMED         Clin ⋯
                                                                   6 columns omitted
    =#

Recursively applying `ImmediateSubtypes` with [`Iterate`](@ref) gives us the
concept set together will all subtypes.

    WithSubtypes() =
        Iterate(:subtype => From(:subtype) |>
                            ImmediateSubtypes())

    q = SNOMED("22298006") |>       # Myocardial infarction
        WithSubtypes()

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    6×10 DataFrame
     Row │ concept_id  concept_name                       domain_id  vocabulary_id ⋯
         │ Int64       String                             String     String        ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │    4329847  Myocardial infarction              Condition  SNOMED        ⋯
       2 │     312327  Acute myocardial infarction        Condition  SNOMED
       3 │     434376  Acute myocardial infarction of a…  Condition  SNOMED
       4 │     438170  Acute myocardial infarction of i…  Condition  SNOMED
       5 │     438438  Acute myocardial infarction of a…  Condition  SNOMED        ⋯
       6 │     444406  Acute subendocardial infarction    Condition  SNOMED
                                                                   6 columns omitted
    =#

Finally, we add operations on a concept set for adding or removing concepts.

    IncludingConcepts(include) =
        Append(include)

    ExcludingConcepts(exclude) =
        LeftJoin(:exclude => exclude,
                 Get.concept_id .== Get.exclude.concept_id) |>
        Where(Fun."is null"(Get.exclude.concept_id))

    q = SNOMED("22298006") |>       # Myocardial infarction
        WithSubtypes() |>
        ExcludingConcepts(
            SNOMED("70422006") |>   # Acute subendocardial infarction
            WithSubtypes())

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    5×10 DataFrame
     Row │ concept_id  concept_name                       domain_id  vocabulary_id ⋯
         │ Int64       String                             String     String        ⋯
    ─────┼──────────────────────────────────────────────────────────────────────────
       1 │    4329847  Myocardial infarction              Condition  SNOMED        ⋯
       2 │     312327  Acute myocardial infarction        Condition  SNOMED
       3 │     434376  Acute myocardial infarction of a…  Condition  SNOMED
       4 │     438170  Acute myocardial infarction of i…  Condition  SNOMED
       5 │     438438  Acute myocardial infarction of a…  Condition  SNOMED        ⋯
                                                                   6 columns omitted
    =#

Given a concept set, it is now easy to find the matching clinical conditions.

    MyocardialInfarctionConcepts() =
        SNOMED("22298006") |>       # Myocardial infarction
        WithSubtypes() |>
        ExcludingConcepts(
            SNOMED("70422006") |>   # Acute subendocardial infarction
            WithSubtypes())

    q = From(:condition_occurrence) |>
        Join(MyocardialInfarctionConcepts(),
             Get.condition_concept_id .== Get.concept_id) |>
        Select(Get.person_id, Get.condition_start_date)

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    6×2 DataFrame
     Row │ person_id  condition_start_date
         │ Int64      String
    ─────┼─────────────────────────────────
       1 │      1780  2008-04-10
       2 │     37455  2010-08-12
       3 │     69985  2010-05-06
       4 │    110862  2008-09-07
       5 │    110862  2008-09-07
       6 │    110862  2010-06-07
    =#

This notation is much more compact and readable than the corresponding SQL
query.

    render(conn, q) |> print
    #=>
    WITH RECURSIVE "subtype_1" ("concept_id") AS (
      SELECT "concept_1"."concept_id"
      FROM "concept" AS "concept_1"
      WHERE
        ("concept_1"."vocabulary_id" = 'SNOMED') AND
        ("concept_1"."concept_code" = '22298006')
      UNION ALL
      SELECT "concept_2"."concept_id"
      FROM "subtype_1"
      JOIN (
        SELECT
          "concept_relationship_1"."concept_id_2",
          "concept_relationship_1"."concept_id_1"
        FROM "concept_relationship" AS "concept_relationship_1"
        WHERE ("concept_relationship_1"."relationship_id" = 'Is a')
      ) AS "concept_relationship_2" ON ("subtype_1"."concept_id" = "concept_relationship_2"."concept_id_2")
      JOIN "concept" AS "concept_2" ON ("concept_relationship_2"."concept_id_1" = "concept_2"."concept_id")
    ),
    "subtype_2" ("concept_id") AS (
      SELECT "concept_3"."concept_id"
      FROM "concept" AS "concept_3"
      WHERE
        ("concept_3"."vocabulary_id" = 'SNOMED') AND
        ("concept_3"."concept_code" = '70422006')
      UNION ALL
      SELECT "concept_4"."concept_id"
      FROM "subtype_2"
      JOIN (
        SELECT
          "concept_relationship_3"."concept_id_2",
          "concept_relationship_3"."concept_id_1"
        FROM "concept_relationship" AS "concept_relationship_3"
        WHERE ("concept_relationship_3"."relationship_id" = 'Is a')
      ) AS "concept_relationship_4" ON ("subtype_2"."concept_id" = "concept_relationship_4"."concept_id_2")
      JOIN "concept" AS "concept_4" ON ("concept_relationship_4"."concept_id_1" = "concept_4"."concept_id")
    )
    SELECT
      "condition_occurrence_1"."person_id",
      "condition_occurrence_1"."condition_start_date"
    FROM "condition_occurrence" AS "condition_occurrence_1"
    JOIN (
      SELECT "subtype_1"."concept_id"
      FROM "subtype_1"
      LEFT JOIN "subtype_2" ON ("subtype_1"."concept_id" = "subtype_2"."concept_id")
      WHERE ("subtype_2"."concept_id" IS NULL)
    ) AS "concept_5" ON ("condition_occurrence_1"."condition_concept_id" = "concept_5"."concept_id")
    =#


## Encapsulating complex SQL expressions

*Show the number of patients diagnosed with myocardial infarction
stratified by the age group at the time of diagnosis.*

In this query, we need to place a person's age into one of the age buckets:
*0 -- 4*, *5 -- 9*, *10 -- 14*, …, *95 -- 99*, *100 +*.  This is a tedious
expression to write in raw SQL, but it could be written very compactly in
FunSQL by using array comprehension to build the conditional expression.

    PersonAgeAt(date) =
        Fun.strftime("%Y", date) .- Get.year_of_birth

    AgeGroup(age) =
        Fun.case(Iterators.flatten([(age .< y, "$(y-5) - $(y-1)")
                                    for y = 5:5:100])...,
                 "100 +")

    ConceptByName(name) =
        From(:concept) |>
        Where(Fun.like(Get.concept_name, "%$(name)%"))

    MyocardialInfarctionConcept() =
        ConceptByName("myocardial infarction")

    MyocardialInfarctionOccurrence() =
        From(:condition_occurrence) |>
        Join(:concept => MyocardialInfarctionConcept(),
             on = Get.condition_concept_id .== Get.concept.concept_id)

    q = From(:person) |>
        Join(:condition => MyocardialInfarctionOccurrence(),
             on = Get.person_id .== Get.condition.person_id) |>
        Group(:age_group => AgeGroup(PersonAgeAt(Get.condition.condition_start_date))) |>
        Select(Get.age_group, Agg.count())

    render(conn, q) |> print
    #=>
    SELECT
      (CASE WHEN ((STRFTIME('%Y', "condition_1"."condition_start_date") - "person_1"."year_of_birth") < 5) THEN '0 - 4' …  ELSE '100 +' END) AS "age_group",
      COUNT(*) AS "count"
    FROM "person" AS "person_1"
    JOIN (
      SELECT
        "condition_occurrence_1"."person_id",
        "condition_occurrence_1"."condition_start_date"
      FROM "condition_occurrence" AS "condition_occurrence_1"
      JOIN (
        SELECT "concept_1"."concept_id"
        FROM "concept" AS "concept_1"
        WHERE ("concept_1"."concept_name" LIKE '%myocardial infarction%')
      ) AS "concept_2" ON ("condition_occurrence_1"."condition_concept_id" = "concept_2"."concept_id")
    ) AS "condition_1" ON ("person_1"."person_id" = "condition_1"."person_id")
    GROUP BY (CASE WHEN ((STRFTIME('%Y', "condition_1"."condition_start_date") - "person_1"."year_of_birth") < 5) THEN '0 - 4' … ELSE '100 +' END)
    =#

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    3×2 DataFrame
     Row │ age_group  count
         │ String     Int64
    ─────┼──────────────────
       1 │ 50 - 54        1
       2 │ 65 - 69        1
       3 │ 95 - 99        4
    =#


## Assembling queries incrementally

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
        From(:concept) |>
        Where(Fun.like(Get.concept_name, "%$(name)%"))

    MyocardialInfarctionConcept() =
        ConceptByName("myocardial infarction")

    MyocardialInfarctionOccurrence() =
        From(:condition_occurrence) |>
        Join(:concept => MyocardialInfarctionConcept(),
             on = Get.condition_concept_id .== Get.concept.concept_id)

    InpatientVisitConcept() =
        ConceptByName("inpatient")

    InpatientVisitOccurrence() =
        From(:visit_occurrence) |>
        Join(:concept => InpatientVisitConcept(),
             on = Get.visit_concept_id .== Get.concept.concept_id)

    CorrelatedInpatientVisit(person_id, date) =
        InpatientVisitOccurrence() |>
        Where(Fun.and(Get.person_id .== Var.PERSON_ID,
                      Fun.between(Var.DATE, Get.visit_start_date, Get.visit_end_date))) |>
        Bind(:PERSON_ID => person_id,
             :DATE => date)

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

    render(conn, q) |> print
    #=>
    SELECT
      "condition_occurrence_2"."person_id",
      "condition_occurrence_2"."condition_start_date"
    FROM (
      SELECT
        "condition_occurrence_1"."person_id",
        "condition_occurrence_1"."condition_start_date",
        (LAG(DATE("condition_occurrence_1"."condition_start_date", '180 days')) OVER (PARTITION BY "condition_occurrence_1"."person_id" ORDER BY "condition_occurrence_1"."condition_start_date")) AS "boundary"
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
        WHERE
          ("visit_occurrence_1"."person_id" = "condition_occurrence_1"."person_id") AND
          ("condition_occurrence_1"."condition_start_date" BETWEEN "visit_occurrence_1"."visit_start_date" AND "visit_occurrence_1"."visit_end_date")
      ))
    ) AS "condition_occurrence_2"
    WHERE (("condition_occurrence_2"."boundary" IS NULL) OR ("condition_occurrence_2"."boundary" < "condition_occurrence_2"."condition_start_date"))
    =#

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    1×2 DataFrame
     Row │ person_id  condition_start_date
         │ Int64      String
    ─────┼─────────────────────────────────
       1 │      1780  2008-04-10
    =#


## Merging overlapping intervals

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

    q = From(:visit_occurrence) |>
        MergeOverlappingIntervals(Get.visit_start_date, Get.visit_end_date) |>
        Select(Get.person_id, Get.start_date, Get.end_date)

    render(conn, q) |> print
    #=>
    SELECT
      "visit_occurrence_3"."person_id",
      MIN("visit_occurrence_3"."visit_start_date") AS "start_date",
      MAX("visit_occurrence_3"."visit_end_date") AS "end_date"
    FROM (
      SELECT
        "visit_occurrence_2"."person_id",
        (SUM("visit_occurrence_2"."new") OVER (PARTITION BY "visit_occurrence_2"."person_id" ORDER BY "visit_occurrence_2"."visit_start_date", (- "visit_occurrence_2"."new") ROWS UNBOUNDED PRECEDING)) AS "period",
        "visit_occurrence_2"."visit_start_date",
        "visit_occurrence_2"."visit_end_date"
      FROM (
        SELECT
          "visit_occurrence_1"."person_id",
          (CASE WHEN ("visit_occurrence_1"."visit_start_date" <= (MAX("visit_occurrence_1"."visit_end_date") OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date" ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING))) THEN 0 ELSE 1 END) AS "new",
          "visit_occurrence_1"."visit_start_date",
          "visit_occurrence_1"."visit_end_date"
        FROM "visit_occurrence" AS "visit_occurrence_1"
      ) AS "visit_occurrence_2"
    ) AS "visit_occurrence_3"
    GROUP BY
      "visit_occurrence_3"."person_id",
      "visit_occurrence_3"."period"
    =#

    DBInterface.execute(conn, q) |> DataFrame
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

*Derive a patient's observation periods by merging visits with less than
one year gap between them.*

    MergeIntervalsByGap(start_date, end_date, gap) =
        MergeOverlappingIntervals(start_date, Fun.date(end_date, gap)) |>
        Define(:end_date => Fun.date(Get.end_date, -gap))

    q = From(:visit_occurrence) |>
        MergeIntervalsByGap(Get.visit_start_date, Get.visit_end_date, Day(365)) |>
        Select(Get.person_id, Get.start_date, Get.end_date)

    render(conn, q) |> print
    #=>
    SELECT
      "visit_occurrence_3"."person_id",
      MIN("visit_occurrence_3"."visit_start_date") AS "start_date",
      DATE(MAX(DATE("visit_occurrence_3"."visit_end_date", '365 days')), '-365 days') AS "end_date"
    FROM (
      SELECT
        "visit_occurrence_2"."person_id",
        (SUM("visit_occurrence_2"."new") OVER (PARTITION BY "visit_occurrence_2"."person_id" ORDER BY "visit_occurrence_2"."visit_start_date", (- "visit_occurrence_2"."new") ROWS UNBOUNDED PRECEDING)) AS "period",
        "visit_occurrence_2"."visit_start_date",
        "visit_occurrence_2"."visit_end_date"
      FROM (
        SELECT
          "visit_occurrence_1"."person_id",
          (CASE WHEN ("visit_occurrence_1"."visit_start_date" <= (MAX(DATE("visit_occurrence_1"."visit_end_date", '365 days')) OVER (PARTITION BY "visit_occurrence_1"."person_id" ORDER BY "visit_occurrence_1"."visit_start_date" ROWS BETWEEN UNBOUNDED PRECEDING AND 1 PRECEDING))) THEN 0 ELSE 1 END) AS "new",
          "visit_occurrence_1"."visit_start_date",
          "visit_occurrence_1"."visit_end_date"
        FROM "visit_occurrence" AS "visit_occurrence_1"
      ) AS "visit_occurrence_2"
    ) AS "visit_occurrence_3"
    GROUP BY
      "visit_occurrence_3"."person_id",
      "visit_occurrence_3"."period"
    =#

    DBInterface.execute(conn, q) |> DataFrame
    #=>
    12×3 DataFrame
     Row │ person_id  start_date  end_date
         │ Int64      String      String
    ─────┼───────────────────────────────────
       1 │      1780  2008-04-09  2009-05-22
       2 │     30091  2008-11-12  2009-08-07
       3 │     37455  2008-03-18  2008-10-30
       4 │     37455  2010-08-12  2010-08-12
       5 │     42383  2009-06-29  2010-04-15
       6 │     69985  2009-01-09  2009-01-09
       7 │     69985  2010-04-17  2010-07-30
       8 │     72120  2008-12-15  2008-12-15
       9 │     82328  2008-10-20  2009-01-25
      10 │     95538  2009-03-30  2009-09-02
      11 │    107680  2009-06-07  2009-07-30
      12 │    110862  2008-09-07  2010-06-07
    =#

