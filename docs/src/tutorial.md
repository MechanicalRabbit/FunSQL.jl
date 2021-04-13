# Tutorial

## Downloading Eunomia Database

In this tutorial, we use the [Eunomia](https://github.com/OHDSI/Eunomia)
dataset containing simulated patient data in [OMOP
CDM](https://github.com/OHDSI/CommonDataModel).  This is a SQLite database,
which you can download from
https://github.com/OHDSI/Eunomia/raw/master/inst/sqlite/cdm.tar.xz.

You can also install it as a Julia artifact.  Run the following code
*once* to create an Artifacts.toml file containing the reference to
the dataset.

    using Pkg.Artifacts

    artifact_toml = joinpath(@__DIR__, "Artifacts.toml")
    eunomia_hash = artifact_hash("eunomia", artifact_toml)

    if eunomia_hash === nothing
        bind_artifact!(
            artifact_toml, "eunomia",
            Base.SHA1("fa13d3ec2d9efe11eddaaab96ada38c5e5a68149"),
            download_info=[("https://github.com/OHDSI/Eunomia/raw/master/inst/sqlite/cdm.tar.xz",
                            "b2828f9484061074982fc8dc7506e479cd1b24ff30a6db14e92426602e18498e")])
        ensure_artifact_installed("eunomia", artifact_toml, quiet_download = true)
    end

Once the dataset is downloaded, it can be accessed with the following
code.

    using Pkg.Artifacts

    eunomia_path = joinpath(artifact"eunomia", "cdm.sqlite")

Now we can create a database connection.

    using SQLite

    const db = SQLite.DB(eunomia_path)


## First Query

    using FunSQL: SQLTable, From, Where, Select, Get, render
    using DataFrames

    person = SQLTable(:person, columns = [:person_id, :year_of_birth])

    q = From(person) |>
        Where(Get.year_of_birth .> 1980) |>
        Select(Get.person_id)

    sql = render(q)
    print(sql)
    #=>
    SELECT "person_1"."person_id"
    FROM "person" AS "person_1"
    WHERE ("person_1"."year_of_birth" > 1980)
    =#

    res = DBInterface.execute(db, sql)

    DataFrame(res)
    #=>
    86×1 DataFrame
     Row │ PERSON_ID
         │ Float64
    ─────┼───────────
       1 │     124.0
       2 │     235.0
       3 │     339.0
       4 │     249.0
       5 │     141.0
       6 │     220.0
       7 │     471.0
       8 │     362.0
      ⋮  │     ⋮
      80 │    4408.0
      81 │    4457.0
      82 │    4781.0
      83 │    4816.0
      84 │    4606.0
      85 │    5343.0
      86 │    5007.0
      71 rows omitted
    =#

We can define a convenience function.

    function run(db, q)
        sql = render(q, dialect = :sqlite)
        res = DBInterface.execute(db, sql)
        DataFrame(res)
    end

    run(db, q)
    #=>
    86×1 DataFrame
     Row │ PERSON_ID
         │ Float64
    ─────┼───────────
       1 │     124.0
       2 │     235.0
       3 │     339.0
       4 │     249.0
       5 │     141.0
       6 │     220.0
       7 │     471.0
       8 │     362.0
      ⋮  │     ⋮
      80 │    4408.0
      81 │    4457.0
      82 │    4781.0
      83 │    4816.0
      84 │    4606.0
      85 │    5343.0
      86 │    5007.0
      71 rows omitted
    =#

