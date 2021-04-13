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

    using FunSQL: SQLTable, From, Where, Select, Get, render
    using DataFrames

    person = SQLTable(:person, columns = [:person_id, :year_of_birth])

    q = From(person) |>
        Where(Get.year_of_birth .> 1950) |>
        Select(Get.person_id)

    sql = render(q)
    print(sql)
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 1950)
    =#

    res = DBInterface.execute(conn, sql)

    DataFrame(res)
    #=>
    3×1 DataFrame
     Row │ person_id
         │ Int64
    ─────┼───────────
       1 │     69985
       2 │     82328
       3 │    107680
    =#

We can define a convenience function.

    function run(conn, q)
        sql = render(q, dialect = :sqlite)
        res = DBInterface.execute(conn, sql)
        DataFrame(res)
    end

    run(conn, q)
    #=>
    3×1 DataFrame
     Row │ person_id
         │ Int64
    ─────┼───────────
       1 │     69985
       2 │     82328
       3 │    107680
    =#

