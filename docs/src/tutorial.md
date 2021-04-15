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

    using FunSQL: SQLTable, Join, From, Where, Select, Get, render
    using DataFrames

    person = SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id])
    location = SQLTable(:location, columns = [:location_id, :city, :state])

    q = person |>
        Join(:location => location,
             on = Get.location_id .== Get.location.location_id,
             left = true) |>
        Where(Get.year_of_birth .> 1950) |>
        Select(Get.person_id, Get.location.state)

    sql = render(q)
    print(sql)
    #=>
    SELECT "person_1"."person_id", "location_1"."state"
    FROM "person" AS "person_1"
    LEFT JOIN "location" AS "location_1" ON ("person_1"."location_id" = "location_1"."location_id")
    WHERE ("person_1"."year_of_birth" > 1950)
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    3×2 DataFrame
     Row │ person_id  state
         │ Int64      String
    ─────┼───────────────────
       1 │     69985  MS
       2 │     82328  NY
       3 │    107680  WA
    =#

We can define a convenience function.

    function run(conn, q)
        sql = render(q, dialect = :sqlite)
        res = DBInterface.execute(conn, sql)
        DataFrame(res)
    end

    run(conn, q)
    #=>
    3×2 DataFrame
     Row │ person_id  state
         │ Int64      String
    ─────┼───────────────────
       1 │     69985  MS
       2 │     82328  NY
       3 │    107680  WA
    =#

