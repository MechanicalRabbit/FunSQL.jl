# Tutorial


## SQL and FunSQL

SQL is a specialized language used for querying and manipulating data in
database management systems.

FunSQL is a Julia library for assembling SQL queries.  It exposes full
expressive power of SQL through a uniform compositional interface.


## Sample Database

Throughout this tutorial, we use a tiny SQLite database containing a 10 person
sample of simulated patient data extracted from the [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).

If you want to follow along with the tutorial, you can download the database
file using the following code.

```julia
const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"
const DB = download(URL)
```

Alternatively, to avoid downloading the file more than once, we can register
the download URL as an [artifact](../Artifacts.toml).

    using Pkg.Artifacts, LazyArtifacts

    const DB = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")

To interact with a SQLite database, we need to install the
[SQLite](https://github.com/JuliaDatabases/SQLite.jl) package.  Once the
package is installed, we can connect to the database.

    using SQLite

    const conn = SQLite.DB(DB)


## Database Schema

The data in the sample database is stored in the format of the [OMOP Common
Data Model](https://ohdsi.github.io/TheBookOfOhdsi/CommonDataModel.html), an
open source database schema for observational healthcare data.  In this
tutorial, we will only use a small fragment of the Common Data Model.

![ERD](erd.drawio.svg)

Before we can start assembling queries with FunSQL, we need to describe
the database schema.  Specifically, for each table in the database, we
need to create a corresponding `SQLTable` object, which will encapsulate the
name of the table and the list of available columns.

    using FunSQL: SQLTable

The patient data, including basic demographic information, is stored in
the table `person`.

    const person =
        SQLTable(:person,
                 columns = [:person_id, :year_of_birth, :location_id])

Patient addresses are stored in a separate table `location`, linked to the
`person` table by the key `location_id`.

    const location =
        SQLTable(:location,
                 columns = [:location_id, :state, :zip])

The bulk of patient data consists of clinical events: encounters with
healthcare providers, recorded observations, diagnosed conditions, prescribed
medications, etc.  In this tutorial we will only use two types of events:
visits and conditions.

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
hypertension* condition) is indicated using a *concept_id* column, which
links to the `concept` table.

    const concept =
        SQLTable(:concept,
                 columns = [:concept_id, :concept_name])

Different concepts may be related to each other.  For instance, *Essential
hypertension* **is a** *Hypertensive disorder*, which itself **is a** *Disorder
of cardiovascular system*.  Concept relationships are recorded in the
corresponding table.

    const concept_relationship =
        SQLTable(:concept_relationship,
                 columns = [:concept_id_1, :concept_id_2, :relationship_id])


## First Query

When was the last time each person born in 1950 or earlier and living in
Illinois was seen by a care provider?

    using FunSQL: Agg, Join, From, Group, Where, Select, Get, render
    using DataFrames

    q = person |>
        Where(Get.year_of_birth .<= 1950) |>
        Join(:location => location,
             on = Get.location_id .== Get.location.location_id) |>
        Where(Get.location.state .== "IL") |>
        Join(:visit_group => visit_occurrence |>
                             Group(Get.person_id),
             on = Get.person_id .== Get.visit_group.person_id,
             left = true) |>
        Select(Get.person_id,
               :max_visit_start_date =>
                   Get.visit_group |> Agg.max(Get.visit_start_date))

    sql = render(q)
    print(sql)
    #=>
    SELECT "person_5"."person_id", "visit_group_1"."max" AS "max_visit_start_date"
    FROM (
      SELECT "person_3"."person_id"
      FROM (
        SELECT "person_1"."location_id", "person_1"."person_id"
        FROM "person" AS "person_1"
        WHERE ("person_1"."year_of_birth" <= 1950)
      ) AS "person_3"
      JOIN "location" AS "location_1" ON ("person_3"."location_id" = "location_1"."location_id")
      WHERE ("location_1"."state" = 'IL')
    ) AS "person_5"
    LEFT JOIN (
      SELECT "visit_occurrence_1"."person_id", MAX("visit_occurrence_1"."visit_start_date") AS "max"
      FROM "visit_occurrence" AS "visit_occurrence_1"
      GROUP BY "visit_occurrence_1"."person_id"
    ) AS "visit_group_1" ON ("person_5"."person_id" = "visit_group_1"."person_id")
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    1×2 DataFrame
     Row │ person_id  max_visit_start_date
         │ Int64      String
    ─────┼─────────────────────────────────
       1 │     72120  2008-12-15
    =#

We can define a convenience function.

    function run(conn, q)
        sql = render(q, dialect = :sqlite)
        res = DBInterface.execute(conn, sql)
        DataFrame(res)
    end

    run(conn, q)
    #=>
    1×2 DataFrame
     Row │ person_id  max_visit_start_date
         │ Int64      String
    ─────┼─────────────────────────────────
       1 │     72120  2008-12-15
    =#

