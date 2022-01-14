# Serialized SQL query with parameter mapping.

"""
Serialized SQL query.
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
    pack(sql::SQLString, vars::Union{Dict, NamedTuple}) :: Vector{Any}

Convert named parameters to positional form.
"""
function pack
end

pack(sql::SQLString, params) =
    pack(sql.vars, params)

pack(vars::Vector{Symbol}, d::AbstractDict{Symbol}) =
    Any[d[var] for var in vars]

pack(vars::Vector{Symbol}, d::AbstractDict{<:AbstractString}) =
    Any[d[String(var)] for var in vars]

pack(vars::Vector{Symbol}, nt::NamedTuple) =
    Any[getproperty(nt, var) for var in vars]

