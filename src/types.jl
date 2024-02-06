# Types for SQL nodes.

abstract type AbstractSQLType
end

Base.show(io::IO, ::MIME"text/plain", t::AbstractSQLType) =
    pprint(io, t)

struct EmptyType <: AbstractSQLType
end

PrettyPrinting.quoteof(::EmptyType) =
    Expr(:call, nameof(EmptyType))

struct ScalarType <: AbstractSQLType
end

PrettyPrinting.quoteof(::ScalarType) =
    Expr(:call, nameof(ScalarType))

struct RowType <: AbstractSQLType
    fields::OrderedDict{Symbol, Union{ScalarType, RowType}}
    group::Union{EmptyType, RowType}

    RowType(fields, group = EmptyType()) =
        new(fields, group)
end

const FieldTypeMap = OrderedDict{Symbol, Union{ScalarType, RowType}}
const GroupType = Union{EmptyType, RowType}

RowType() =
    RowType(FieldTypeMap())

RowType(fields::Pair{Symbol, <:AbstractSQLType}...; group = EmptyType()) =
    RowType(FieldTypeMap(fields), group)

function PrettyPrinting.quoteof(t::RowType)
    ex = Expr(:call, nameof(RowType))
    for (f, ft) in t.fields
        push!(ex.args, Expr(:call, :(=>), QuoteNode(f), quoteof(ft)))
    end
    if !(t.group isa EmptyType)
        push!(ex.args, Expr(:kw, :group, quoteof(t.group)))
    end
    ex
end

const EMPTY_ROW = RowType()


# Type of `Append` (UNION ALL).

Base.intersect(::AbstractSQLType, ::AbstractSQLType) =
    EmptyType()

Base.intersect(::ScalarType, ::ScalarType) =
    ScalarType()

function Base.intersect(t1::RowType, t2::RowType)
    if t1 === t2
        return t1
    end
    fields = FieldTypeMap()
    for f in keys(t1.fields)
        if f in keys(t2.fields)
            t = intersect(t1.fields[f], t2.fields[f])
            if !isa(t, EmptyType)
                fields[f] = t
            end
        end
    end
    group = intersect(t1.group, t2.group)
    RowType(fields, group)
end


# Type order.

Base.issubset(::AbstractSQLType, ::AbstractSQLType) =
    false

Base.issubset(::EmptyType, ::AbstractSQLType) =
    true

Base.issubset(::ScalarType, ::ScalarType) =
    true

function Base.issubset(t1::RowType, t2::RowType)
    if t1 === t2
        return true
    end
    for f in keys(t1.fields)
        if !(f in keys(t2.fields) && issubset(t1.fields[f], t2.fields[f]))
            return false
        end
    end
    if !issubset(t1.group, t2.group)
        return false
    end
    return true
end
