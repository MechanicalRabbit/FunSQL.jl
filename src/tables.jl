# Structure of a SQL table.

using PrettyPrinting: PrettyPrinting, pprint, quoteof

"""
    SQLTable(; schema = nothing, name, columns)
    SQLTable(name; schema = nothing, columns)
    SQLTable(name, columns...; schema = nothing)

The structure of a SQL table or a table-like entity (TEMP TABLE, VIEW, etc) for
use as a reference in assembling SQL queries.

The `SQLTable` constructor expects the table `name`, a vector `columns` of
column names, and, optionally, the name of the table `schema`.  A name can be
provided as a `Symbol` or `String` value.

# Examples
```julia-repl
>>> SQLTable(:location,
             :location_id, :address_1, :address_2, :city, :state, :zip);

>>> SQLTable(schema = "public",
             name = "person",
             columns = ["person_id", "birth_datetime", "location_id"]);
```
"""
struct SQLTable
    schema::Union{Symbol, Nothing}
    name::Symbol
    columns::Vector{Symbol}

    SQLTable(;
             schema::Union{Symbol, AbstractString, Nothing} = nothing,
             name::Union{Symbol, AbstractString},
             columns::AbstractVector{<:Union{Symbol, AbstractString}}) =
        new(schema !== nothing ? Symbol(schema) : nothing,
            Symbol(name),
            !isa(columns, Vector{Symbol}) ?
                Symbol[Symbol(col) for col in columns] :
                columns)
end

SQLTable(name; schema = nothing, columns) =
    SQLTable(schema = schema, name = name, columns = columns)

SQLTable(name, columns...; schema = nothing) =
    SQLTable(schema = schema, name = name, columns = [columns...])

function Base.show(io::IO, tbl::SQLTable)
    name = replace(string(tbl.name), '"' => "\"\"")
    print(io, "SQLTable \"$name\"")
end

Base.show(io::IO, ::MIME"text/plain", tbl::SQLTable) =
    pprint(io, tbl)

PrettyPrinting.quoteof(tbl::SQLTable) =
    Expr(:call,
         nameof(SQLTable),
         (tbl.schema !== nothing ? Any[Expr(:kw, :schema, quoteof(tbl.schema))] : [])...,
         quoteof(tbl.name),
         Any[quoteof(col) for col in tbl.columns]...)

