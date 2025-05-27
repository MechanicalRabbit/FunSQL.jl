# Other Tests


## `SQLConnection` and `SQLStatement`

A `SQLConnection` object encapsulates a raw database connection together
with the database catalog.

    using FunSQL: SQLConnection, SQLCatalog, SQLTable
    using Pkg.Artifacts, LazyArtifacts
    using SQLite
    using Tables

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

The output of the statement is wrapped in a FunSQL-specific `SQLCursor`
object.

    cr = DBInterface.execute(stmt)
    #-> SQLCursor(SQLite.Query{false}( … ))

`SQLCursor` implements standard interfaces by delegating supported methods
to the wrapped cursor object.

    eltype(cr)
    #-> SQLite.Row

    for row in cr
        println(row)
    end
    #=>
    SQLite.Row{false}:
     :person_id      1780
     :year_of_birth  1940
    ⋮
    =#

    DBInterface.lastrowid(cr)
    #-> 0

    Tables.schema(cr)
    #=>
    Tables.Schema:
     :person_id      Union{Missing, Int64}
     :year_of_birth  Union{Missing, Int64}
    =#

    cr = DBInterface.execute(stmt)
    Tables.rowtable(cr)
    #-> @NamedTuple{ … }[(person_id = 1780, year_of_birth = 1940), … ]

    cr = DBInterface.execute(stmt)
    Tables.columntable(cr)
    #-> (person_id = [1780, … ], year_of_birth = [1940, … ])

    DBInterface.close!(stmt)

    DBInterface.close!(cr)

For a query with parameters, this allows us to specify the parameter values
by name.

    using FunSQL: Get, Var, Where

    q = From(:person) |>
        Where(Get.year_of_birth .>= Var.YEAR)

    stmt = DBInterface.prepare(conn, q)
    #-> SQLStatement(SQLConnection( … ), SQLite.Stmt( … ), vars = [:YEAR])

    DBInterface.execute(stmt, YEAR = 1950)
    #-> SQLCursor(SQLite.Query{false}( … ))

    DBInterface.close!(stmt)

    DBInterface.close!(conn)


## `SQLCatalog`, `SQLTable`, and `SQLColumn`

In FunSQL, tables and table-like entities are represented using `SQLTable`
objects.  Their columns are represented using `SQLColumn` objects.
A collection of `SQLTable` objects is represented as a `SQLCatalog`
object.

    using FunSQL: SQLCatalog, SQLColumn, SQLTable

A `SQLTable` constructor takes the table name, a vector of columns, and,
optionally, the name of the table schema and other qualifiers.  A name
could be provided either as a `Symbol` or as a `String` value.  A column
can be specified just by its name.

    location = SQLTable(qualifiers = [:public],
                        name = :location,
                        columns = [:location_id, :address_1, :address_2,
                                   :city, :state, :zip])
    #-> SQLTable(qualifiers = [:public], :location, …)

    person = SQLTable(name = "person",
                      columns = ["person_id", "year_of_birth", "location_id"])
    #-> SQLTable(:person, …)

The table and the column names could be provided as positional arguments.

    concept = SQLTable("concept", "concept_id", "concept_name", "vocabulary_id")
    #-> SQLTable(:concept, …)

A column may have a custom name for use with FunSQL and the original name
for generating SQL queries.

    vocabulary = SQLTable(:vocabulary,
                          :id => SQLColumn(:vocabulary_id),
                          :name => SQLColumn(:vocabulary_name))
    #-> SQLTable(:vocabulary, …)

A `SQLTable` object is displayed as a Julia expression that created
the object.

    display(location)
    #=>
    SQLTable(qualifiers = [:public],
             :location,
             SQLColumn(:location_id),
             SQLColumn(:address_1),
             SQLColumn(:address_2),
             SQLColumn(:city),
             SQLColumn(:state),
             SQLColumn(:zip))
    =#

    display(vocabulary)
    #=>
    SQLTable(:vocabulary,
             :id => SQLColumn(:vocabulary_id),
             :name => SQLColumn(:vocabulary_name))
    =#

A `SQLTable` object behaves like a read-only dictionary.

    person[:person_id]
    #-> SQLColumn(:person_id)

    person["person_id"]
    #-> SQLColumn(:person_id)

    person[1]
    #-> SQLColumn(:person_id)

    person[:visit_occurrence]
    #-> ERROR: KeyError: key :visit_occurrence not found

    get(person, :person_id, nothing)
    #-> SQLColumn(:person_id)

    get(person, "person_id", nothing)
    #-> SQLColumn(:person_id)

    get(person, :visit_occurrence, missing)
    #-> missing

    get(() -> missing, person, :visit_occurrence)
    #-> missing

    length(person)
    #-> 3

    collect(keys(person))
    #-> [:person_id, :year_of_birth, :location_id]

A `SQLCatalog` constructor takes a collection of `SQLTable` objects,
the target dialect, and the size of the query cache.  Just as columns,
a table may have a custom name for use with FunSQL and the original name
for generating SQL.

    catalog = SQLCatalog(tables = [person, location, concept, :concept_vocabulary => vocabulary],
                         dialect = :sqlite,
                         cache = 128)
    #-> SQLCatalog(…4 tables…, dialect = SQLDialect(:sqlite), cache = 128)

    display(catalog)
    #=>
    SQLCatalog(SQLTable(:concept,
                        SQLColumn(:concept_id),
                        SQLColumn(:concept_name),
                        SQLColumn(:vocabulary_id)),
               :concept_vocabulary => SQLTable(:vocabulary,
                                               :id => SQLColumn(:vocabulary_id),
                                               :name => SQLColumn(
                                                            :vocabulary_name)),
               SQLTable(qualifiers = [:public],
                        :location,
                        SQLColumn(:location_id),
                        SQLColumn(:address_1),
                        SQLColumn(:address_2),
                        SQLColumn(:city),
                        SQLColumn(:state),
                        SQLColumn(:zip)),
               SQLTable(:person,
                        SQLColumn(:person_id),
                        SQLColumn(:year_of_birth),
                        SQLColumn(:location_id)),
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
    #-> SQLCatalog(dialect = SQLDialect(), cache = (Dict{Any, Any})())

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
    #-> [:concept, :concept_vocabulary, :location, :person]

Catalog objects can be assigned arbitrary metadata.

    metadata_catalog =
        SQLCatalog(SQLTable(:person,
                            SQLColumn(:person_id, metadata = (; label = "Person ID")),
                            SQLColumn(:year_of_birth, metadata = (;)),
                            metadata = (; caption = "Person", is_view = false)),
                   metadata = (; model = "OMOP"))
    #-> SQLCatalog(…1 table…, dialect = SQLDialect(), metadata = …)

    display(metadata_catalog)
    #=>
    SQLCatalog(SQLTable(:person,
                        SQLColumn(:person_id, metadata = [:label => "Person ID"]),
                        SQLColumn(:year_of_birth),
                        metadata = [:caption => "Person", :is_view => false]),
               dialect = SQLDialect(),
               metadata = [:model => "OMOP"])
    =#

FunSQL metadata supports DataAPI metadata interface.

    using DataAPI

    DataAPI.metadata(metadata_catalog)
    #-> Dict("model" => "OMOP")

    DataAPI.metadata(metadata_catalog, style = true)
    #-> Dict("model" => ("OMOP", :default))

    DataAPI.metadata(metadata_catalog, :name, :default)
    #-> :default

    DataAPI.metadata(metadata_catalog[:person])["caption"]
    #-> "Person"

    DataAPI.metadata(metadata_catalog[:person], :is_view, true)
    #-> false

    DataAPI.colmetadata(metadata_catalog[:person])[:person_id]["label"]
    #-> "Person ID"

    DataAPI.colmetadata(metadata_catalog[:person], 1, :label)
    #-> "Person ID"

    DataAPI.colmetadata(metadata_catalog[:person], :year_of_birth, :label, "")
    #-> ""

    DataAPI.metadata(metadata_catalog[:person][:person_id])
    #-> Dict("label" => "Person ID")

    DataAPI.metadata(metadata_catalog[:person][:person_id], :label, "")
    #-> "Person ID"


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
                                         variable_prefix = '?',
                                         variable_style = :positional)
    #-> SQLDialect(:postgresql, …)

    display(postgresql_odbc_dialect)
    #-> SQLDialect(:postgresql, variable_prefix = '?', variable_style = :POSITIONAL)

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

`SQLString` may carry a vector `columns` describing the output columns of
the query.

    sql = SQLString("SELECT person_id FROM person", columns = [SQLColumn(:person_id)])
    #-> SQLString("SELECT person_id FROM person", columns = […1 column…])

    display(sql)
    #-> SQLString("SELECT person_id FROM person", columns = [SQLColumn(:person_id)])

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

