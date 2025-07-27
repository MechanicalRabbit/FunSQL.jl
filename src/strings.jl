# Serialized SQL query with parameter mapping.

"""
    SQLString(raw; vars = Symbol[], shape = SQLTable(:_))

Serialized SQL query.

Parameter `vars` is a vector of query parameters (created with [`Var`](@ref))
in the order they are expected by the `DBInterface.execute()` function.

Parameter `shape` describes the shape of the query output as a table
definition.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> render(q)
SQLString(\"""
          SELECT
            "person_1"."person_id",
            "person_1"."year_of_birth"
          FROM "person" AS "person_1\\"\""",
          shape = SQLTable(:person,
                           SQLColumn(:person_id),
                           SQLColumn(:year_of_birth)))

julia> q = From(person) |> Where(Fun.and(Get.year_of_birth .>= Var.YEAR,
                                         Get.year_of_birth .< Var.YEAR .+ 10));

julia> render(q, dialect = :mysql)
SQLString(\"""
          SELECT
            `person_1`.`person_id`,
            `person_1`.`year_of_birth`
          FROM `person` AS `person_1`
          WHERE
            (`person_1`.`year_of_birth` >= ?) AND
            (`person_1`.`year_of_birth` < (? + 10))\""",
          vars = [:YEAR, :YEAR],
          shape = SQLTable(:person,
                           SQLColumn(:person_id),
                           SQLColumn(:year_of_birth)))

julia> render(q, dialect = :postgresql)
SQLString(\"""
          SELECT
            "person_1"."person_id",
            "person_1"."year_of_birth"
          FROM "person" AS "person_1"
          WHERE
            ("person_1"."year_of_birth" >= \$1) AND
            ("person_1"."year_of_birth" < (\$1 + 10))\""",
          vars = [:YEAR],
          shape = SQLTable(:person,
                           SQLColumn(:person_id),
                           SQLColumn(:year_of_birth)))
```
"""
struct SQLString <: AbstractString
    raw::String
    vars::Vector{Symbol}
    shape::SQLTable

    SQLString(raw; vars = Symbol[], shape = SQLTable(name = :_, columns = [])) =
        new(raw, vars, shape)
end

Base.ncodeunits(str::SQLString) =
    ncodeunits(str.raw)

Base.codeunit(str::SQLString) =
    codeunit(str.raw)

@Base.propagate_inbounds Base.codeunit(str::SQLString, i::Integer) =
    codeunit(str.raw, i)

@Base.propagate_inbounds Base.isvalid(str::SQLString, i::Integer) =
    isvalid(str.raw, i)

@Base.propagate_inbounds Base.iterate(str::SQLString, i::Integer = 1) =
    iterate(str.raw, i)

Base.String(str::SQLString) =
    str.raw

Base.print(io::IO, str::SQLString) =
    print(io, str.raw)

Base.write(io::IO, str::SQLString) =
    write(io, str.raw)

function PrettyPrinting.quoteof(str::SQLString)
    ex = Expr(:call, nameof(SQLString), str.raw)
    if !isempty(str.vars)
        push!(ex.args, Expr(:kw, :vars, quoteof(str.vars)))
    end
    if str.shape.name !== :_ || !isempty(str.shape.columns) || !isempty(str.shape.metadata)
        push!(ex.args, Expr(:kw, :shape, quoteof(str.shape)))
    end
    ex
end

function Base.show(io::IO, str::SQLString)
    print(io, "SQLString(")
    show(io, str.raw)
    if !isempty(str.vars)
        print(io, ", vars = ")
        show(io, str.vars)
    end
    if str.shape.name !== :_ || !isempty(str.shape.columns)
        print(io, ", shape = SQLTable(", str.shape.name)
        l = length(str.shape.columns)
        print(io, l == 0 ? ")" : l == 1 ? ", …1 column…)" : ", …$l columns…)")
    end
    print(io, ')')
    nothing
end

Base.show(io::IO, ::MIME"text/plain", str::SQLString) =
    pprint(io, str)

DataAPI.metadatasupport(::Type{SQLString}) =
    DataAPI.metadatasupport(SQLTable)

DataAPI.metadata(str::SQLString, key; style = false) =
    DataAPI.metadata(str.shape, key; style)

DataAPI.metadata(str::SQLString, key, default; style = false) =
    DataAPI.metadata(str.shape, key, default; style)

DataAPI.metadatakeys(str::SQLString) =
    DataAPI.metadatakeys(str.shape)

DataAPI.colmetadatasupport(::Type{SQLString}) =
    DataAPI.colmetadatasupport(SQLTable)

DataAPI.colmetadata(str::SQLString, col, key; style = false) =
    DataAPI.colmetadata(str.shape, col, key; style)

DataAPI.colmetadata(str::SQLString, col, key, default; style = false) =
    DataAPI.colmetadata(str.shape, col, key, default; style)

DataAPI.colmetadatakeys(str::SQLString) =
    DataAPI.colmetadatakeys(str.shape)

DataAPI.colmetadatakeys(str::SQLString, col) =
    DataAPI.colmetadatakeys(str.shape, col)

"""
    pack(str::SQLString, vars::Union{Dict, NamedTuple})::Vector{Any}

Convert a dictionary or a named tuple of query parameters to the positional
form expected by `DBInterface.execute()`.

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |> Where(Fun.and(Get.year_of_birth .>= Var.YEAR,
                                         Get.year_of_birth .< Var.YEAR .+ 10));

julia> str = render(q, dialect = :mysql);

julia> pack(str, (; YEAR = 1950))
2-element Vector{Any}:
 1950
 1950

julia> str = render(q, dialect = :postgresql);

julia> pack(str, (; YEAR = 1950))
1-element Vector{Any}:
 1950
```
"""
function pack
end

pack(str::SQLString, params) =
    pack(str.vars, params)

pack(str::AbstractString, params) =
    params

pack(vars::Vector{Symbol}, d::AbstractDict{Symbol}) =
    Any[d[var] for var in vars]

pack(vars::Vector{Symbol}, d::AbstractDict{<:AbstractString}) =
    Any[d[String(var)] for var in vars]

pack(vars::Vector{Symbol}, nt::NamedTuple) =
    Any[getproperty(nt, var) for var in vars]
