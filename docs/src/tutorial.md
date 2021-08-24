# Tutorial

```@meta
CurrentModule = FunSQL
```

This tutorial will teach you how to build SQL queries using FunSQL.


## Test Database

To demonstrate database queries, we need a test database.  The database we use
here is a tiny 10 person sample of simulated patient data extracted from a much
larger [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).
For a database engine, we picked [SQLite](https://www.sqlite.org/).  Using
SQLite in a tutorial is convenient because it does not require a database
server to run and allows us to distribute the whole database as a single file.
FunSQL supports SQLite and many other database engines.  The techniques
discussed here are not specific to SQLite or this particular database.  Once
you learn them, you should be able to apply them to your own databases.

If you wish to follow along with the tutorial and run the examples, download
the database file:

```julia
const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"
const DB = download(URL)
```

During development, all the code examples here are executed on every update by
the [NarrativeTest](https://github.com/MechanicalRabbit/NarrativeTest.jl)
package.  To avoid downloading the database file more than once, we registered
the download URL as an [artifact](../Artifacts.toml) and use
[`Pkg.Artifacts`](http://pkgdocs.julialang.org/v1/artifacts/) API to fetch it:

    using Pkg.Artifacts, LazyArtifacts

    const DB = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")

To interact with a SQLite database from Julia code, we need to install the
[SQLite](https://github.com/JuliaDatabases/SQLite.jl) package:

```julia
using Pkg

Pkg.add("SQLite")
```

Once the package is installed, we can use it to connect to the database:

    using SQLite

    const conn = SQLite.DB(DB)

Later we will use the `conn` object to execute database queries.


## Database Schema

The data in the test database is stored in the format of the [OMOP Common
Data Model](https://ohdsi.github.io/TheBookOfOhdsi/CommonDataModel.html), an
open source database schema for observational healthcare data.  In this
tutorial, we will only use a small fragment of the Common Data Model.

![Fragment of the OMOP Common Data Model](omop-common-data-model.drawio.svg)

Before we can start assembling queries with FunSQL, we need to make FunSQL
aware of the database schema.  For each table in the database, we need to
create a corresponding [`SQLTable`](@ref) object, which encapsulates the name
of the table together with the names of the columns.

    using FunSQL: SQLTable

The patient data, including basic demographic information, is stored in
the table `person`:

    const person =
        SQLTable(:person,
                 columns = [:person_id, :year_of_birth, :location_id])

Patient addresses are stored in a separate table `location`, linked to the
`person` table by the key column `location_id`:

    const location =
        SQLTable(:location,
                 columns = [:location_id, :city, :state])

The bulk of patient data consists of clinical events: visits to healthcare
providers, recorded observations, diagnosed conditions, prescribed medications,
etc.  In this tutorial we only use two types of events, visits and conditions:

    const visit_occurrence =
        SQLTable(:visit_occurrence,
                 columns = [:visit_occurrence_id, :person_id,
                            :visit_concept_id,
                            :visit_start_date, :visit_end_date])

    const condition_occurrence =
        SQLTable(:condition_occurrence,
                 columns = [:condition_occurrence_id, :person_id,
                            :condition_concept_id,
                            :condition_start_date, :condition_end_date])

The specific type of the event (e.g., *Inpatient* visit or *Essential
hypertension* condition) is indicated using a *concept id* column, which
refers to the `concept` table:

    const concept =
        SQLTable(:concept,
                 columns = [:concept_id, :concept_name])

Different concepts may be related to each other.  For instance, *Essential
hypertension* **is a** *Hypertensive disorder*, which itself **is a** *Disorder
of cardiovascular system*.  Concept relationships are recorded in the
corresponding table:

    const concept_relationship =
        SQLTable(:concept_relationship,
                 columns = [:concept_id_1, :concept_id_2, :relationship_id])


## Why FunSQL?

Let us start with clarifying why you may want to use FunSQL.  Consider
a problem:

*Find all patients born between 1930 and 1940 and living in Illinois,
and for each patient show their current age (by the end of 2020).*

The answer can be obtained with the following SQL query:

```sql
SELECT p.person_id, 2020 - p.year_of_birth AS age
FROM person p
JOIN location l ON (p.location_id = l.location_id)
WHERE (p.year_of_birth BETWEEN 1930 AND 1940) AND (l.state = 'IL')
```

The simplest way to incorporate this query into Julia code is to embed it as a
string literal:

    sql = """
    SELECT p.person_id, 2020 - p.year_of_birth AS age
    FROM person p
    JOIN location l ON (p.location_id = l.location_id)
    WHERE (p.year_of_birth BETWEEN 1930 AND 1940) AND (l.state = 'IL')
    """

Using an appropriate [database engine
API](https://juliadatabases.org/SQLite.jl/stable/#DBInterface.execute) and the
connection object created [earlier](@ref Test-Database), we can execute this
query and get back the answer:

    res = DBInterface.execute(conn, sql)
    #-> SQLite.Query( … )

As an aside, it is convenient to use the
[DataFrame](https://github.com/JuliaData/DataFrames.jl) interface to show the
output of a query in tabular form:

    using DataFrames

    res |> DataFrame |> display
    #=>
    1×2 DataFrame
     Row │ person_id  age
         │ Int64      Int64
    ─────┼──────────────────
       1 │     72120     83
    =#

FunSQL introduces an extra step to this workflow.  Instead of embedding the SQL
query directly into Julia code, we construct a *query object*:

    using FunSQL: From, Fun, Get, Join, Select, Where

    q = From(person) |>
        Where(Fun.between(Get.year_of_birth, 1930, 1940)) |>
        Join(:location => From(location) |>
                          Where(Get.state .== "IL"),
             on = Get.location_id .== Get.location.location_id) |>
        Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

The value of `q` is a composite object of type [`SQLNode`](@ref).  "Composite"
means that `q` is assembled from components (also of type `SQLNode`), which
themselves are either atomic or assembled from smaller components.  Different
kinds of components are created by `SQLNode` constructors such as `From`,
`Where`, `Fun`, `Get`, etc.

The actual SQL query is generated by *rendering* the query object:

    using FunSQL: render

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_3"."person_id", (2020 - "person_3"."year_of_birth") AS "age"
    FROM (
      SELECT "person_1"."location_id", "person_1"."person_id", "person_1"."year_of_birth"
      FROM "person" AS "person_1"
      WHERE ("person_1"."year_of_birth" BETWEEN 1930 AND 1940)
    ) AS "person_3"
    JOIN (
      SELECT "location_1"."location_id"
      FROM "location" AS "location_1"
      WHERE ("location_1"."state" = 'IL')
    ) AS "location_3" ON ("person_3"."location_id" = "location_3"."location_id")
    =#

Notice that the [`render`](@ref) function takes a parameter called `dialect`.
Although the SQL language is standardized, different implementations of SQL
tend to deviate from the standard far enough to make them mutually
incompatible.  For this reason, FunSQL lets us select the target SQL dialect.

At this point, the job of FunSQL is done and, just as before, we can execute
the query and display the result:

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    1×2 DataFrame
     Row │ person_id  age
         │ Int64      Int64
    ─────┼──────────────────
       1 │     72120     83
    =#

Why, instead of embedding a complete SQL query, we may prefer to generate it
through a query object?  To justify this extra step, consider that in a real
Julia program, any query is likely going to be parameterized:

*Find all patients born between `$start_year` and `$end_year` and living in
`$states`, and for each patient show the `$output_columns`.*

If this is the case, the SQL query cannot be prepared in advance and must be
assembled on the fly.  While it is possible to assemble a SQL query from string
fragments, it is tedious, error-prone and definitely not fun.  FunSQL provides
a more robust and effective approach: build the query as a composite data
structure.

Here is how a parameterized query may be constructed with FunSQL:

    function FindPatients(; start_year = nothing,
                            end_year = nothing,
                            states = String[])
        q = From(person) |>
            Where(BirthRange(start_year, end_year))
        if !isempty(states)
            q = q |>
                Join(:location => From(location) |>
                                  Where(Fun.in(Get.state, states...)),
                     on = Get.location_id .== Get.location.location_id)
        end
        q
    end

    function BirthRange(start_year, end_year)
        p = true
        if start_year !== nothing
            p = Fun.and(p, Get.year_of_birth .>= start_year)
        end
        if end_year !== nothing
            p = Fun.and(p, Get.year_of_birth .<= end_year)
        end
        p
    end

The function `FindPatients` effectively becomes a new `SQLNode` constructor,
which can be used directly or as a component of a larger query:

    q = FindPatients()

    print(render(q, dialect = :sqlite))
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth", "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

    q = FindPatients(start_year = 1930) |>
        Select(Get.person_id)

    print(render(q, dialect = :sqlite))
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" >= 1930)
    =#

    q = FindPatients(start_year = 1930, end_year = 1940, states = ["IL"]) |>
        Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

    print(render(q, dialect = :sqlite))
    #=>
    SELECT "person_3"."person_id", (2020 - "person_3"."year_of_birth") AS "age"
    FROM (
      SELECT "person_1"."location_id", "person_1"."person_id", "person_1"."year_of_birth"
      FROM "person" AS "person_1"
      WHERE (("person_1"."year_of_birth" >= 1930) AND ("person_1"."year_of_birth" <= 1940))
    ) AS "person_3"
    JOIN (
      SELECT "location_1"."location_id"
      FROM "location" AS "location_1"
      WHERE ("location_1"."state" IN ('IL'))
    ) AS "location_3" ON ("person_3"."location_id" = "location_3"."location_id")
    =#


## Assembling Queries

Recall the query that was demonstrated in the [previous section](@ref
Why-FunSQL?):

*Find all patients born between 1930 and 1940 and living in Illinois,
and for each patient show their current age.*

    From(person) |>
    Where(Fun.between(Get.year_of_birth, 1930, 1940)) |>
    Join(:location => From(location) |>
                      Where(Get.state .== "IL"),
         on = Get.location_id .== Get.location.location_id) |>
    Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

Now we are going to describe various components of this query and how they are
assembled together.  At the outer level, this query is constructed from tabular
operations `From`, `Where`, `Join`, and `Select` arranged in a pipeline by the
pipe (`|>`) operator.  In SQL, a *tabular operation* takes a certain number of
input datasets and produces an output dataset.  It is helpful to visualize a
tabular operation as a node with a certain number of input arrows and one
output arrow.

![From, Where, Select, and Join nodes](from-where-select-join-nodes.drawio.svg)

Then the whole query can be visualized as a pipeline diagram.  Each arrow in
this diagram represents a dataset, and each node represents an elementary data
processing operation.

![Query pipeline](person-by-birth-year-range-and-state.drawio.svg)

The following tabular operations are available in FunSQL.

| Constructor           | Function                                          |
| :-------------------- | :------------------------------------------------ |
| [`Append`](@ref)      | concatenate datasets                              |
| [`As`](@ref)          | wrap all columns in a nested record               |
| [`Bind`](@ref)        | correlate a subquery in a *join* expression       |
| [`Define`](@ref)      | add an output column                              |
| [`From`](@ref)        | produce the content of a database table           |
| [`Group`](@ref)       | partition the dataset into disjoint groups        |
| [`Join`](@ref)        | correlate two datasets                            |
| [`Limit`](@ref)       | truncate the dataset                              |
| [`Order`](@ref)       | sort the dataset                                  |
| [`Partition`](@ref)   | add a window to the dataset                       |
| [`Select`](@ref)      | specify output columns                            |
| [`Where`](@ref)       | filter the dataset by the given condition         |

We will take a closer look at three of them: `From`, `Select`, and `Join`.

The `From` node outputs the content of a database table.  The constructor
takes one argument, a `SQLTable` object (see the section [Database
Schema](@ref)).  In a query, a bare `SQLTable` object is automatically
converted to a `From` node, so one could write more compactly:

    person |>
    Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

It is possible for a query not to have a `From` node:

*Show the current date and time.*

    q = Select(Fun.current_timestamp())

    sql = render(q)

    print(sql)
    #-> SELECT CURRENT_TIMESTAMP AS "current_timestamp"

In this query, the `Select` node is not connected to any source of data.  In
such a case, it is supplied with a *unit dataset* containing one row and no
columns.  Hence this query will generate one row of output.

In general, the `Select` node is used to specify the output columns.  The name
of the column is either derived from the expression or set explicitly with `As`
(or its shorthand `=>`).

As opposed to SQL, FunSQL does not demand that all queries have an explicit
`Select`.  The following query will produce all columns of the table:

*Show all patients.*

    q = From(person)

    sql = render(q)

    print(sql)
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth", "person_1"."location_id"
    FROM "person" AS "person_1"
    =#

The `Join` node correlates the rows of two input datasets.  Predominantly,
`Join` is used for looking up table records by key.  In the following example,
`Join` associates each `person` record with their `location` using the key
column `location_id` that uniquely identifies a `location` record:

*Show all patients together with their state of residence.*

    person |>
    Join(:location => location,
         Get.location_id .== Get.location.location_id,
         left = true) |>
    Select(Get.person_id, Get.location.state)

The modifier `left = true` tells `Join` that it must output all `person`
records including those without the corresponding `location`.  Since this is a
very common requirement, FunSQL provides an alias:

    using FunSQL: LeftJoin

    person |>
    LeftJoin(:location => location,
             Get.location_id .== Get.location.location_id) |>
    Select(Get.person_id, Get.location.state)

Since `Join` needs two input datasets, it must be attached to two input
pipelines.  The first pipeline is attached using the `|>` operator and the
second one is provided as an argument to the `Join` constructor.
Alternatively, both input pipelines can be specified as keyword arguments:

    Join(over = person,
         joinee = :location => location,
         on = Get.location_id .== Get.location.location_id,
         left = true)

The output of `Join` combines columns of both input datasets, which will cause
ambiguity if both datasets have a column with the same name.  Such is the case
in the previous example since both tables, `person` and `location`, have a
column called `location_id`.  To disambiguate them, we can place all columns of
one of the datasets into a nested record.  This is the action of the arrow
(`=>`) operator or its full form, the `As` node:

    using FunSQL: As

    From(person) |>
    LeftJoin(From(location) |>
             As(:location),
             on = Get.location_id .== Get.location.location_id)
    Select(Get.person_id, Get.location.state)

Alternatively, we could use *bound column references*, which are described
later in this section.

Many tabular operations including `Join`, `Select` and `Where` are
parameterized with row operations.  A *row operation* acts on an individual row
of a dataset and produces a scalar value.  Row operations are assembled from
literal values, column references, and applications of SQL functions and
operators.  Below is a list of row operations available in FunSQL.

| Constructor           | Function                                          |
| :-------------------- | :------------------------------------------------ |
| [`Agg`](@ref)         | apply an aggregate function                       |
| [`As`](@ref)          | assign a column alias                             |
| [`Bind`](@ref)        | correlate a subquery                              |
| [`Fun`](@ref)         | apply a scalar function or a scalar operator      |
| [`Get`](@ref)         | produce the value of a column                     |
| [`Lit`](@ref)         | produce a constant value                          |
| [`Sort`](@ref)        | indicate the sort order                           |
| [`Var`](@ref)         | produce the value of a query parameter            |

The `Lit` constructor creates a literal value, although we could usually omit
the constructor:

    using FunSQL: Lit

    Select(Lit(42))
    Select(42)

The SQL value `NULL` is represented by the Julia constant `missing`:

    q = Select(missing)

    sql = render(q, dialect = :sqlite)

    print(sql)
    #-> SELECT NULL AS "_"

The `Get` constructor creates a column reference.  `Get` admits several
equivalent forms:

    Get.year_of_birth
    Get(:year_of_birth)
    Get."year_of_birth"
    Get("year_of_birth")

Such column references are resolved at the place of use against the input
dataset.  As we mentioned earlier, sometimes column references cannot be
resolved unambiguously.  To alleviate this problem, we can bind the column
reference to the node that produces it:

    qₚ = From(person)
    qₗ = From(location)
    q = qₚ |>
        LeftJoin(qₗ, on = qₚ.location_id .== qₗ.location_id) |>
        Select(qₚ.person_id, qₗ.state)

The notation `qₚ.location_id` and `qₗ.location_id` is just syntax sugar for

    qₚ |> Get(:location_id)
    qₗ |> Get(:location_id)

SQL functions and operators are represented using the `Fun` constructor, which
also has several equivalent forms:

    Fun.between(Get.year_of_birth, 1930, 1940)
    Fun(:between, Get.year_of_birth, 1930, 1940)
    Fun."between"(Get.year_of_birth, 1930, 1940)
    Fun("between", Get.year_of_birth, 1930, 1940)

Certain SQL operators, notably comparison operators, can be represented using
Julia broadcasting notation:

    Fun.">="(Get.year_of_birth, 1930)
    Get.year_of_birth .>= 1930

We should note that FunSQL does not verify if a SQL function or an operator is
used correctly or even whether or not it exists.  In such a case, FunSQL will
generate a SQL query that fails to execute:

    q = From(person) |>
        Select(Fun.frobnicate(Get.year_of_birth))

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT FROBNICATE("person_1"."year_of_birth") AS "frobnicate"
    FROM "person" AS "person_1"
    =#

    DBInterface.execute(conn, sql)
    #-> ERROR: SQLite.SQLiteException("no such function: FROBNICATE")

On the other hand, FunSQL will correctly serialize many SQL functions and
operators that have irregular syntax including `AND`, `OR`, `NOT`, `IN`,
`EXISTS`, `CASE`, and others:

*Show the demographic cohort of each patient.*

    q = From(person) |>
        Select(Fun.case(Get.year_of_birth .<= 1060, "boomer", "millenial"))

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT (CASE WHEN ("person_1"."year_of_birth" <= 1060) THEN 'boomer' ELSE 'millenial' END) AS "case"
    FROM "person" AS "person_1"
    =#

