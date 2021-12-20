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

struct AmbiguousType <: AbstractSQLType
end

PrettyPrinting.quoteof(::AmbiguousType) =
    Expr(:call, nameof(AmbiguousType))

struct RowType <: AbstractSQLType
    fields::OrderedDict{Symbol, Union{ScalarType, AmbiguousType, RowType}}
    group::Union{EmptyType, AmbiguousType, RowType}

    RowType(fields, group = EmptyType()) =
        new(fields, group)
end

const FieldTypeMap = OrderedDict{Symbol, Union{ScalarType, AmbiguousType, RowType}}
const GroupType = Union{EmptyType, AmbiguousType, RowType}
const HandleTypeMap = Dict{Int, Union{AmbiguousType, RowType}}

RowType() =
    RowType(FieldTypeMap())

RowType(fields::Pair{Symbol, <:AbstractSQLType}...; group = EmptyType()) =
    RowType(FieldTypeMap(fields...), group)

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

struct BoxType <: AbstractSQLType
    name::Symbol
    row::RowType
    handle_map::HandleTypeMap
end

BoxType(name::Symbol, row::RowType) =
    BoxType(name, row, HandleTypeMap())

function BoxType(name::Symbol, fields::Pair{<:Union{Symbol, Int}, <:AbstractSQLType}...; group = EmptyType())
    field_map = FieldTypeMap()
    handle_map = HandleTypeMap()
    for (key, val) in fields
        if key isa Symbol
            field_map[key] = val
        else
            handle_map[key] = val
        end
    end
    BoxType(name, RowType(field_map, group), handle_map)
end

function PrettyPrinting.quoteof(t::BoxType)
    ex = Expr(:call, nameof(BoxType), QuoteNode(t.name))
    for (f, ft) in t.row.fields
        push!(ex.args, Expr(:call, :(=>), QuoteNode(f), quoteof(ft)))
    end
    if !(t.row.group isa EmptyType)
        push!(ex.args, Expr(:kw, :group, quoteof(t.row.group)))
    end
    for (h, ht) in sort!(collect(t.handle_map))
        push!(ex.args, Expr(:call, :(=>), h, quoteof(ht)))
    end
    ex
end

const EMPTY_BOX = BoxType(:_, RowType(), HandleTypeMap())

function add_handle(t::BoxType, handle::Int)
    if handle != 0
        handle_map = copy(t.handle_map)
        handle_map[handle] = t.row
        t = BoxType(t.name, t.row, handle_map)
    end
    t
end


# Type of `Append` (UNION ALL).

Base.intersect(::AbstractSQLType, ::AbstractSQLType) =
    EmptyType()

Base.intersect(::ScalarType, ::ScalarType) =
    ScalarType()

Base.intersect(::AmbiguousType, ::AmbiguousType) =
    AmbiguousType()

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

function Base.intersect(t1::BoxType, t2::BoxType)
    if t1 === t2
        return t1
    end
    handle_map = HandleTypeMap()
    for h in keys(t1.handle_map)
        if h in keys(t2.handle_map)
            t = intersect(t1.handle_map[h], t2.handle_map[h])
            if !(t isa EmptyType)
                handle_map[h] = t
            end
        end
    end
    name = t1.name == t2.name ? t2.name : :union
    BoxType(name, intersect(t1.row, t2.row), handle_map)
end

Base.issubset(::AbstractSQLType, ::AbstractSQLType) =
    false

Base.issubset(::T, ::T) where {T <: AbstractSQLType} =
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
    return true
end

function Base.issubset(t1::BoxType, t2::BoxType)
    if t1 === t2
        return true
    end
    t1.name == t2.name || return false
    issubset(t1.row, t2.row) || return false
    for h in keys(t1.handle_map)
        if !(h in keys(t2.handle_map) && issubset(t1.handle_map[h], t2.handle_map[h]))
            return false
        end
    end
    return true
end

# Type of `Join`.

Base.union(::AbstractSQLType, ::AbstractSQLType) =
    AmbiguousType()

Base.union(::EmptyType, ::EmptyType) =
    EmptyType()

Base.union(::EmptyType, t::AbstractSQLType) =
    t

Base.union(t::AbstractSQLType, ::EmptyType) =
    t

Base.union(::ScalarType, ::ScalarType) =
    ScalarType()

function Base.union(t1::RowType, t2::RowType)
    fields = FieldTypeMap()
    for (f, t) in t1.fields
        if f in keys(t2.fields)
            t′ = t2.fields[f]
            if t isa RowType && t′ isa RowType
                t = union(t, t′)
            else
                t = AmbiguousType()
            end
        end
        fields[f] = t
    end
    for (f, t) in t2.fields
        if !(f in keys(t1.fields))
            fields[f] = t
        end
    end
    if t1.group isa EmptyType
        group = t2.group
    elseif t2.group isa EmptyType
        group = t1.group
    else
        group = AmbiguousType()
    end
    RowType(fields, group)
end

function Base.union(t1::BoxType, t2::BoxType)
    handle_map = HandleTypeMap()
    for l in keys(t1.handle_map)
        if haskey(t2.handle_map, l)
            handle_map[l] = AmbiguousType()
        else
            handle_map[l] = t1.handle_map[l]
        end
    end
    for l in keys(t2.handle_map)
        if !haskey(t1.handle_map, l)
            handle_map[l] = t2.handle_map[l]
        end
    end
    BoxType(t1.name, union(t1.row, t2.row), handle_map)
end

