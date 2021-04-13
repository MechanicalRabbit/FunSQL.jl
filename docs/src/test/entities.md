# SQL Entities

In FunSQL, tables and table-like entities are represented using `SQLTable`
objects.

    using FunSQL: SQLTable

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
