# `SQLCatalog` and `SQLTable`

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

    SQLCatalog(person)
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

    display(collect(catalog))
    #=>
    4-element Vector{Pair{Symbol, SQLTable}}:
         :person => SQLTable(:person, …)
       :location => SQLTable(:location, schema = :public, …)
     :vocabulary => SQLTable(:vocabulary, …)
        :concept => SQLTable(:concept, …)
    =#

