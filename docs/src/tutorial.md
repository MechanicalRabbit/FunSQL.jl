# Tutorial


## Sample Database

Throughout this tutorial, we use a tiny SQLite database containing a 10 person
sample of simulated patient data, which is extracted from the [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).

If you want to follow along with the tutorial, download the database file:

```julia
const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"
const DB = download(URL)
```

To avoid downloading the file more than once, we can register the download URL
as an [artifact](../Artifacts.toml) and use
[`Pkg.Artifacts`](http://pkgdocs.julialang.org/v1/artifacts/) API to fetch it:

    using Pkg.Artifacts, LazyArtifacts

    const DB = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")

In order to interact with a SQLite database, we need to install the
[SQLite](https://github.com/JuliaDatabases/SQLite.jl) package.  Once the
package is installed, we could establish a database connection:

    using SQLite

    const conn = SQLite.DB(DB)


## Database Schema

The data in the sample database is stored in the format of the [OMOP Common
Data Model](https://ohdsi.github.io/TheBookOfOhdsi/CommonDataModel.html), an
open source database schema for observational healthcare data.  In this
tutorial, we will only use a small fragment of the Common Data Model.

![Fragment of the OMOP Common Data Model](omop-common-data-model.drawio.svg)

Before we can start assembling queries with FunSQL, we need to make FunSQL
aware of the database schema.  Specifically, for each table in the database, we
need to create a corresponding `SQLTable`(@ref) object, which encapsulates the
table name and its columns.

    using FunSQL: SQLTable

The patient data, including basic demographic information, is stored in
the table `person`:

    const person =
        SQLTable(:person,
                 columns = [:person_id, :year_of_birth, :location_id])

Patient addresses are stored in a separate table `location`, linked to the
`person` table by the key `location_id`:

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


## Using FunSQL

To retrieve data from the database using FunSQL, we need to perform three
steps: assemble a query object, render SQL, and execute SQL.  To demonstrate
these steps, let us consider the following question:

*Who are the patients born between 1930 and 1940 and what is their current
age (by the end of 2020)?*

The SQL query that answer this question could be written like this:

```sql
SELECT p.person_id, 2020 - p.year_of_birth AS age
FROM person p
WHERE p.year_of_birth >= 1930 AND p.year_of_birth < 1940
```

FunSQL representation of the SQL query mirrors its structure:
the structure of the SQL query:

    using FunSQL: From, Fun, Get, Select, Where

    q = From(person) |>
        Where(Fun.and(Get.year_of_birth .>= 1930,
                      Get.year_of_birth .< 1940)) |>
        Select(Get.person_id,
               :age => 2020 .- Get.year_of_birth)

The next step is to serialize the query object to SQL.  We need to specify the
target SQL dialect such as `:sqlite` or `:postgresql`:

    using FunSQL: render

    sql = render(q, dialect = :sqlite)

    print(sql)
    #=>
    SELECT "person_1"."person_id", (2020 - "person_1"."year_of_birth") AS "age"
    FROM "person" AS "person_1"
    WHERE (("person_1"."year_of_birth" >= 1930) AND ("person_1"."year_of_birth" < 1940))
    =#

At this point, the job of FunSQL is done.  To submit the SQL query to the
database engine, we can use the connection object that we created
[earlier](@ref Sample-Database):

    res = DBInterface.execute(conn, sql)
    #-> SQLite.Query( … )

The output of the query could be displayed in a tabular form by converting it
to a [`DataFrame`](https://github.com/JuliaData/DataFrames.jl) object:

    using DataFrames

    res |> DataFrame |> display
    #=>
    2×2 DataFrame
     Row │ person_id  age
         │ Int64      Int64
    ─────┼──────────────────
       1 │     30091     88
       2 │     72120     83
    =#


## Tabular operations

Recall the query demonstrated in the [previous](@ref Using-FunSQL) section:

    From(person) |>
    Where(Fun.and(Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)) |>
    Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

This query is constructed from tabular operations `From`, `Where`, and `Select`
arranged in a pipeline using the pipe (`|>`) operator.

In SQL, a *tabular operation* takes a certain number of input datasets and
produces an output dataset.  Tabular operations are typically parameterized by
*row operations*, which act on a dataset row and produce a scalar value.

The `From` operation outputs the content of a database table.  It takes one
argument, a `SQLTable` object describing the table (see section [Database
Schema](@ref) for the definition of `person`).  In the context of a query
expression, a `SQLTable` object is automatically converted to `From`;
thus this query could condensed to:

    person |>
    Where(Fun.and(Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)) |>
    Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

The `Select` operation allows us to customize the output columns.  Column
names are specified with `=>` or using the `As` constructor, e.g.,

    using FunSQL: As

    2020 .- Get.year_of_birth |> As(:age)

If the column name is not given explicitly, it is derived from the expression
that calculates the column value.

As opposed to SQL, FunSQL does not require that the query has an explicit
`Select`, so that the following expression is a valid and complete query:

    q = From(person) |>
        Where(Fun.and(Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940))

This query produces all the columns from the `person` table:

    sql = render(q)

    print(sql)
    #=>
    SELECT "person_1"."person_id", "person_1"."year_of_birth", "person_1"."location_id"
    FROM "person" AS "person_1"
    WHERE (("person_1"."year_of_birth" >= 1930) AND ("person_1"."year_of_birth" < 1940))
    =#

Neither `From` is mandatory.  When a tabular operation, such as `Select`, that
expects an input dataset isn't provided with one, it is supplied with the
*unit* dataset containing one row and no columns.  This allows us to create
queries that do not depend on the content of any database tables and generate
one row of output:

    q = Select(Fun.current_timestamp())

    sql = render(q)

    print(sql)
    #-> SELECT CURRENT_TIMESTAMP AS "current_timestamp"


## Row operations

Row operations are assembled from literal values, column references, and
applications of SQL functions and operators.

Literal values are created using the `Lit` constructor, although the values
of type `Bool`, `Number`, `AbstractString` and `AbstractTime` as well as
`missing` are automatically wrapped with `Lit` when used in a query
expression:

    using FunSQL: Lit

    Select(Lit(42))
    Select(42)

The SQL value `NULL` is represented by `missing`.  FunSQL makes a reasonable
attempt to convert Julia values to their respective SQL equivalents.

Column references are created using the `Get` constructor, which has several
equivalent forms:

    Get.year_of_birth
    Get(:year_of_birth)
    Get."year_of_birth"
    Get("year_of_birth")

Column references are always resolved at the place of use.  Here, the same
reference `Get.year_of_birth` appears several times:

    From(person) |>
    Where(Fun.and(Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)) |>
    Select(Get.person_id, :age => 2020 .- Get.year_of_birth)

As a part of `Where`, it refers to the column produced by the `From` operation,
but inside `Select` it refers to the output of `Where`.

FunSQL provides an alternative notation for column references.

    q1 = From(person)
    q2 = q1 |>
         Where(Fun.and(q1.year_of_birth .>= 1930, q1.year_of_birth .< 1940))
    q3 = q2 |>
         Select(q1.person_id, :age => 2020 .- q1.year_of_birth)

The *unbound* references `Get.year_of_birth` and `Get.person_id` are replaced
with *bound* references `q1.year_of_birth` and `q1.person_id`.  If we use a
bound reference, the node to which the reference is bound must be a part of the
query.  Note that in `Select`, we could replace `q1` with `q2` without changing
the meaning of the query:

    q3 = q2 |>
         Select(q2.person_id, :age => 2020 .- q2.year_of_birth)

Use of unbound references makes query composition more modular.  For example,
we could encapsulate the condition on the birth range in a Julia function
as follows:

    BirthRange(start, stop) =
        Fun.and(Get.year_of_birth .>= start, Get.year_of_birth .< stop)

    From(person) |> Where(BirthRange(1930, 1940))

On the other hand, bound references sometimes make it easier to disambiguate
columns of different tables.

SQL functions and operators are represented using the `Fun` constructor,
which, just like `Get`, has several equivalent forms:

    Fun.and(Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)
    Fun(:and, Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)
    Fun."and"(Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)
    Fun("and", Get.year_of_birth .>= 1930, Get.year_of_birth .< 1940)

Certain SQL operators, notably comparison operators, also support broadcasting
notation:

    Fun.">="(Get.year_of_birth, 1930)
    Get.year_of_birth .>= 1930

FunSQL has support for serializing some of the widely used SQL functions and
operators with irregular notation.  For example:

    q = From(person) |>
        Select(:generation => Fun.case(Get.year_of_birth .<= 1960,
                                       "boomer", "millenial"))

    print(render(q))
    #=>
    SELECT (CASE WHEN ("person_1"."year_of_birth" <= 1960) THEN 'boomer' ELSE 'millenial' END) AS "generation"
    FROM "person" AS "person_1"
    =#

