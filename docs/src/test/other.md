# Other Tests


## `SQLConnection` and `SQLStatement`

A `SQLConnection` object encapsulates a raw database connection together
with the database catalog.

    using FunSQL: SQLConnection, SQLCatalog, SQLTable
    using Pkg.Artifacts, LazyArtifacts
    using SQLite

    const DATABASE = joinpath(artifact"synpuf-10p", "synpuf-10p.sqlite")

    raw_conn = DBInterface.connect(SQLite.DB, DATABASE)

    person = SQLTable(:person, columns = [:person_id, :year_of_birth])

    catalog = SQLCatalog(person, dialect = :sqlite)

    conn = SQLConnection(raw_conn, catalog = catalog)
    #-> SQLConnection(SQLite.DB( … ), catalog = SQLCatalog(…1 table…, dialect = SQLDialect(:sqlite)))

`SQLConnection` delegates `DBInterface` calls to the raw connection object.

    DBInterface.prepare(conn, "SELECT * FROM person")
    #-> SQLite.Stmt( … )

    DBInterface.execute(conn, "SELECT * FROM person")
    #-> SQLite.Query{false}( … )

When `DBInterface.prepare` is applied to a query node, it returns
a FunSQL-specific `SQLStatement` object.

    using FunSQL: From

    q = From(:person)

    stmt = DBInterface.prepare(conn, q)
    #-> SQLStatement(SQLConnection( … ), SQLite.Stmt( … ))

    DBInterface.getconnection(stmt)
    #-> SQLConnection( … )

    DBInterface.execute(stmt)
    #-> SQLite.Query{false}( … )

    DBInterface.close!(stmt)

For a query with parameters, this allows us to specify the parameter values
by name.

    using FunSQL: Get, Var, Where

    q = From(:person) |>
        Where(Get.year_of_birth .>= Var.YEAR)

    stmt = DBInterface.prepare(conn, q)
    #-> SQLStatement(SQLConnection( … ), SQLite.Stmt( … ), vars = [:YEAR])

    DBInterface.execute(stmt, YEAR = 1950)
    #-> SQLite.Query{false}( … )

    DBInterface.close!(stmt)

    DBInterface.close!(conn)


## `SQLCatalog` and `SQLTable`

In FunSQL, tables and table-like entities are represented using `SQLTable`
objects.  A collection of `SQLTable` objects is represented as a `SQLCatalog`
object.

    using FunSQL: SQLCatalog, SQLTable

A `SQLTable` constructor takes the table name, a vector of column names,
and, optionally, the name of the table schema.  A name could be provided
either as a `Symbol` or as a `String` value.

    location = SQLTable(schema = :public,
                        name = :location,
                        columns = [:location_id, :address_1, :address_2,
                                   :city, :state, :zip])
    #-> SQLTable(:location, schema = :public, …)

    person = SQLTable(name = "person",
                      columns = ["person_id", "year_of_birth", "location_id"])
    #-> SQLTable(:person, …)

The table and the column names could be provided as positional arguments.

    vocabulary = SQLTable(:vocabulary,
                          columns = [:vocabulary_id, :vocabulary_name])
    #-> SQLTable(:vocabulary, …)

    concept = SQLTable("concept", "concept_id", "concept_name", "vocabulary_id")
    #-> SQLTable(:concept, …)

A `SQLTable` object is displayed as a Julia expression that created
the object.

    display(location)
    #=>
    SQLTable(:location,
             schema = :public,
             columns = [:location_id, :address_1, :address_2, :city, :state, :zip])
    =#

    display(person)
    #=>
    SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id])
    =#

A `SQLCatalog` constructor takes a collection of `SQLTable` objects,
the target dialect, and the size of the query cache.

    catalog = SQLCatalog(tables = [person, location, vocabulary, concept],
                         dialect = :sqlite,
                         cache = 128)
    #-> SQLCatalog(…4 tables…, dialect = SQLDialect(:sqlite), cache = 128)

    display(catalog)
    #=>
    SQLCatalog(
        :concept => SQLTable(:concept,
                             columns =
                                 [:concept_id, :concept_name, :vocabulary_id]),
        :location =>
            SQLTable(
                :location,
                schema = :public,
                columns =
                    [:location_id, :address_1, :address_2, :city, :state, :zip]),
        :person => SQLTable(:person,
                            columns = [:person_id, :year_of_birth, :location_id]),
        :vocabulary => SQLTable(:vocabulary,
                                columns = [:vocabulary_id, :vocabulary_name]),
        dialect = SQLDialect(:sqlite),
        cache = 128)
    =#

Number of tables in the catalog affects its representation.

    SQLCatalog(tables = [:person => person])
    #-> SQLCatalog(…1 table…, dialect = SQLDialect())

    SQLCatalog()
    #-> SQLCatalog(dialect = SQLDialect())

The query cache can be completely disabled.

    cacheless_catalog = SQLCatalog(cache = nothing)
    #-> SQLCatalog(dialect = SQLDialect(), cache = nothing)

    display(cacheless_catalog)
    #-> SQLCatalog(dialect = SQLDialect(), cache = nothing)

Any `Dict`-like object can serve as a query cache.

    customcache_catalog = SQLCatalog(cache = Dict())
    #-> SQLCatalog(dialect = SQLDialect(), cache = Dict{Any, Any}())

    display(customcache_catalog)
    #-> SQLCatalog(dialect = SQLDialect(), cache = Dict{Any, Any}())

The catalog behaves as a read-only `Dict` object.

    catalog[:person]
    #-> SQLTable(:person, …)

    catalog["person"]
    #-> SQLTable(:person, …)

    catalog[:visit_occurrence]
    #-> ERROR: KeyError: key :visit_occurrence not found

    get(catalog, :person, nothing)
    #-> SQLTable(:person, …)

    get(catalog, "person", nothing)
    #-> SQLTable(:person, …)

    get(catalog, :visit_occurrence, missing)
    #-> missing

    get(() -> missing, catalog, :visit_occurrence)
    #-> missing

    length(catalog)
    #-> 4

    sort(collect(keys(catalog)))
    #-> [:concept, :location, :person, :vocabulary]


## `SQLDialect`

In FunSQL, properties and capabilities of a particular SQL dialect
are encapsulated in a `SQLDialect` object.

    using FunSQL: SQLDialect

The desired dialect can be specified by name.

    postgresql_dialect = SQLDialect(:postgresql)
    #-> SQLDialect(:postgresql)

    display(postgresql_dialect)
    #-> SQLDialect(:postgresql)

If necessary, the dialect can be customized.

    postgresql_odbc_dialect = SQLDialect(:postgresql,
                                         variable_style = :positional,
                                         variable_prefix = '?')
    #-> SQLDialect(:postgresql, …)

    display(postgresql_odbc_dialect)
    #-> SQLDialect(:postgresql, variable_style = :POSITIONAL, variable_prefix = '?')

The default dialect does not correspond to any particular database server.

    default_dialect = SQLDialect()
    #-> SQLDialect()

    display(default_dialect)
    #-> SQLDialect()

A completely custom dialect can be specified.

    my_dialect = SQLDialect(:my, identifier_quotes = ('<', '>'))
    #-> SQLDialect(name = :my, …)

    display(my_dialect)
    #-> SQLDialect(name = :my, identifier_quotes = ('<', '>'))


## `SQLString`

`SQLString` represents a serialized SQL query.

    using FunSQL: SQLString, pack

    sql = SQLString("SELECT * FROM person")
    #-> SQLString("SELECT * FROM person")

    display(sql)
    #-> SQLString("SELECT * FROM person")

`SQLString` implements the `AbstractString` interface.

    ncodeunits(sql)
    #-> 20

    codeunit(sql)
    #-> UInt8

    codeunit(sql, 1)
    #-> 0x53

    isvalid(sql, 1)
    #-> true

    join(collect(sql))
    #-> "SELECT * FROM person"

    print(sql)
    #-> SELECT * FROM person

    write(IOBuffer(), sql)
    #-> 20

    String(sql)
    #-> "SELECT * FROM person"

When the query has parameters, `SQLString` should include a vector of
parameter names in the order they should appear in `DBInterface.execute` call.

    sql = SQLString("SELECT * FROM person WHERE year_of_birth >= ?", vars = [:YEAR])
    #-> SQLString("SELECT * FROM person WHERE year_of_birth >= ?", vars = [:YEAR])

    display(sql)
    #-> SQLString("SELECT * FROM person WHERE year_of_birth >= ?", vars = [:YEAR])

Function `pack` converts named parameters to the positional form suitable
for use with `DBInterface.execute`.

    pack(sql, (; YEAR = 1950))
    #-> Any[1950]

    pack(sql, Dict(:YEAR => 1950))
    #-> Any[1950]

    pack(sql, Dict("YEAR" => 1950))
    #-> Any[1950]

`pack` can also be applied to a regular string, in which case it returns
the parameters unchanged.

    pack("SELECT * FROM person WHERE year_of_birth >= ?", (1950,))
    #-> (1950,)

