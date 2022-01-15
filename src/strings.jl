# Serialized SQL query with parameter mapping.

"""
    SQLString(raw, vars = Symbol[])

Serialized SQL query.

Parameter `vars` is a vector of query parameters (created with [`Var`](@ref))
in the order they are expected by the `DBInterface.execute()` function.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person);

julia> render(q)
SQLString(\"""
          SELECT
            "person_1"."person_id",
            "person_1"."year_of_birth"
          FROM "person" AS "person_1\\"\""")

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
          vars = [:YEAR, :YEAR])

julia> render(q, dialect = :postgresql)
SQLString(\"""
          SELECT
            "person_1"."person_id",
            "person_1"."year_of_birth"
          FROM "person" AS "person_1"
          WHERE
            ("person_1"."year_of_birth" >= \$1) AND
            ("person_1"."year_of_birth" < (\$1 + 10))\""",
          vars = [:YEAR])
```
"""
struct SQLString <: AbstractString
    raw::String
    vars::Vector{Symbol}

    SQLString(raw; vars = Symbol[]) =
        new(raw, vars)
end

Base.ncodeunits(sql::SQLString) =
    ncodeunits(sql.raw)

Base.codeunit(sql::SQLString) =
    codeunit(sql.raw)

@Base.propagate_inbounds Base.codeunit(sql::SQLString, i::Integer) =
    codeunit(sql.raw, i)

@Base.propagate_inbounds Base.isvalid(sql::SQLString, i::Integer) =
    isvalid(sql.raw, i)

@Base.propagate_inbounds Base.iterate(sql::SQLString, i::Integer = 1) =
    iterate(sql.raw, i)

Base.String(sql::SQLString) =
    sql.raw

Base.print(io::IO, sql::SQLString) =
    print(io, sql.raw)

Base.write(io::IO, sql::SQLString) =
    write(io, sql.raw)

function PrettyPrinting.quoteof(sql::SQLString)
    ex = Expr(:call, nameof(SQLString), sql.raw)
    if !isempty(sql.vars)
        push!(ex.args, Expr(:kw, :vars, quoteof(sql.vars)))
    end
    ex
end

function Base.show(io::IO, sql::SQLString)
    print(io, "SQLString(")
    show(io, sql.raw)
    if !isempty(sql.vars)
        print(io, ", vars = ")
        show(io, sql.vars)
    end
    print(io, ')')
    nothing
end

Base.show(io::IO, ::MIME"text/plain", sql::SQLString) =
    pprint(io, sql)

"""
    pack(sql::SQLString, vars::Union{Dict, NamedTuple})::Vector{Any}

Convert a dictionary or a named tuple of query parameters to the positional
form expected by `DBInterface.execute()`.

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |> Where(Fun.and(Get.year_of_birth .>= Var.YEAR,
                                         Get.year_of_birth .< Var.YEAR .+ 10));

julia> sql = render(q, dialect = :mysql);

julia> pack(sql, (; YEAR = 1950))
2-element Vector{Any}:
 1950
 1950

julia> sql = render(q, dialect = :postgresql);

julia> pack(sql, (; YEAR = 1950))
1-element Vector{Any}:
 1950
```
"""
function pack
end

pack(sql::SQLString, params) =
    pack(sql.vars, params)

pack(sql::AbstractString, params) =
    params

pack(vars::Vector{Symbol}, d::AbstractDict{Symbol}) =
    Any[d[var] for var in vars]

pack(vars::Vector{Symbol}, d::AbstractDict{<:AbstractString}) =
    Any[d[String(var)] for var in vars]

pack(vars::Vector{Symbol}, nt::NamedTuple) =
    Any[getproperty(nt, var) for var in vars]

