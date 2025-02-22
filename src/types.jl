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
    visible::Bool

    ScalarType(; visible = true) =
        new(visible)
end

function PrettyPrinting.quoteof(t::ScalarType)
    ex = Expr(:call, nameof(ScalarType))
    if !t.visible
        push!(ex.args, Expr(:kw, :visible, t.visible))
    end
    ex
end

struct RowType <: AbstractSQLType
    fields::OrderedDict{Symbol, Union{ScalarType, RowType}}
    group::Union{EmptyType, RowType}
    visible::Bool

    RowType(fields, group = EmptyType(); visible = true) =
        new(fields, group, visible)
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
    if !t.visible
        push!(ex.args, Expr(:kw, :visible, t.visible))
    end
    ex
end

const EMPTY_ROW = RowType()


# Type of `Append` (UNION ALL).

Base.intersect(::AbstractSQLType, ::AbstractSQLType) =
    EmptyType()

Base.intersect(t1::ScalarType, t2::ScalarType) =
    ScalarType(visible = t1.visible || t2.visible)

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
    RowType(fields, group, visible = t1.visible || t2.visible)
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
    if !t1.visible && t2.visible
        return false
    end
    return true
end
