# Tutorial

## Sample Database

In this tutorial, we consider a tiny SQLite database with a 10 person sample of
simulated patient data extracted from [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).

The SQLite database file can be downloaded with the following code.

```julia
const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"
const DB = download(URL)
```

Alternatively, we can create an [`Artifacts.toml`](../Artifacts.toml) file with
a link to the database in order to avoid downloading the file more than once.

    using Pkg.Artifacts, LazyArtifacts

    const DB = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")
    #-> ⋮

Next, we create a connection to the database.

    using SQLite

    const conn = SQLite.DB(DB)

## First Query

When was the last time each person born in 1950 or earlier and living in
Illinois was seen by a care provider?

    using FunSQL: SQLTable, Agg, Join, From, Group, Where, Select, Get, render
    using DataFrames

    const person =
        SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id])
    const location =
        SQLTable(:location, columns = [:location_id, :city, :state])
    const visit_occurrence =
        SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date])

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

