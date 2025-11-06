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
    ScalarType() =
        new()
end

function PrettyPrinting.quoteof(t::ScalarType)
    Expr(:call, nameof(ScalarType))
end

struct RowType <: AbstractSQLType
    fields::OrderedDict{Symbol, Union{ScalarType, RowType}}
    group::Union{EmptyType, RowType}
    private_fields::Set{Symbol}

    RowType(fields, group = EmptyType(), private_fields = Set{Symbol}()) =
        new(fields, group, private_fields)
end

const FieldTypeMap = OrderedDict{Symbol, Union{ScalarType, RowType}}
const GroupType = Union{EmptyType, RowType}

RowType() =
    RowType(FieldTypeMap())

RowType(fields::Pair{Symbol, <:AbstractSQLType}...; group = EmptyType(), private_fields = Set{Symbol}()) =
    RowType(FieldTypeMap(fields), group, private_fields)

function PrettyPrinting.quoteof(t::RowType)
    ex = Expr(:call, nameof(RowType))
    for (f, ft) in t.fields
        push!(ex.args, Expr(:call, :(=>), QuoteNode(f), quoteof(ft)))
    end
    if !(t.group isa EmptyType)
        push!(ex.args, Expr(:kw, :group, quoteof(t.group)))
    end
    if !isempty(t.private_fields)
        push!(ex.args, Expr(:kw, :private_fields, t.private_fields))
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
    private_fields = Set{Symbol}()
    for f in keys(t1.fields)
        if f in keys(t2.fields)
            t = intersect(t1.fields[f], t2.fields[f])
            if !isa(t, EmptyType)
                fields[f] = t
                if f in t1.private_fields && f in t2.private_fields
                    push!(private_fields, f)
                end
            end
        end
    end
    group = intersect(t1.group, t2.group)
    RowType(fields, group, private_fields)
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
        if !(f in keys(t2.fields) && issubset(t1.fields[f], t2.fields[f]) && (!(f in t1.private_fields) || f in t2.private_fields))
            return false
        end
    end
    if !issubset(t1.group, t2.group)
        return false
    end
    return true
end
