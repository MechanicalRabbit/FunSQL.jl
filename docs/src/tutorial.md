# Tutorial

## Downloading Eunomia Database

In this tutorial, we consider a tiny sample (10 people) of simulated patient
data extracted from [CMS DE-SynPuf
dataset](https://www.cms.gov/Research-Statistics-Data-and-Systems/Downloadable-Public-Use-Files/SynPUFs/DE_Syn_PUF).
This data is stored in a SQLite database, which can be downloaded from
https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite.

    const URL = "https://github.com/MechanicalRabbit/ohdsi-synpuf-demo/releases/download/20210412/synpuf-10p.sqlite"

    using SQLite

    const db = SQLite.DB(download(URL))


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

    res = DBInterface.execute(db, sql)

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

    function run(db, q)
        sql = render(q, dialect = :sqlite)
        res = DBInterface.execute(db, sql)
        DataFrame(res)
    end

    run(db, q)
    #=>
    3×1 DataFrame
     Row │ person_id
         │ Int64
    ─────┼───────────
       1 │     69985
       2 │     82328
       3 │    107680
    =#

