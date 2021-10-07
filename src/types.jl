# Types of SQL nodes.

abstract type AbstractSQLType
end

struct EmptyType <: AbstractSQLType
end

PrettyPrinting.quoteof(::EmptyType) =
    Expr(:call, nameof(EmptyType))

struct RowType <: AbstractSQLType
    fields::OrderedDict{Symbol, AbstractSQLType}
    group::AbstractSQLType

    RowType(fields, group = EmptyType()) =
        new(fields, group)
end

RowType() =
    RowType(OrderedDict{Symbol, AbstractSQLType}())

function PrettyPrinting.quoteof(t::RowType)
    ex = Expr(:call, nameof(RowType))
    if qctx.limit
        push!(ex.args, :…)
    else
        push!(ex.args, quoteof(t.fields))
        if !(t.group isa EmptyType)
            push!(ex.args, quoteof(t.group))
        end
    end
    ex
end

function PrettyPrinting.quoteof(d::Dict{Symbol, AbstractSQLType})
    ex = Expr(:call, nameof(Dict))
    for (k, v) in d
        push!(ex.args, Expr(:call, :(=>), QuoteNode(k), quoteof(v)))
    end
    ex
end

struct ScalarType <: AbstractSQLType
end

PrettyPrinting.quoteof(::ScalarType) =
    Expr(:call, nameof(ScalarType))

struct AmbiguousType <: AbstractSQLType
end

PrettyPrinting.quoteof(::AmbiguousType) =
    Expr(:call, nameof(AmbiguousType))

struct ExportType
    name::Symbol
    row::RowType
    handle_map::Dict{Int, RowType}
end

Base.intersect(::AbstractSQLType, ::AbstractSQLType) =
    EmptyType()

Base.intersect(::ScalarType, ::ScalarType) =
    ScalarType()

Base.intersect(::AmbiguousType, ::AmbiguousType) =
    AmbiguousType()

function Base.intersect(t1::RowType, t2::RowType)
    fields = OrderedDict{Symbol, AbstractSQLType}()
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

function Base.intersect(t1::ExportType, t2::ExportType)
    handle_map = Dict{Int, RowType}()
    for h in keys(t1.handle_map)
        if h in keys(t2.handle_map)
            t = intersect(t1.handle_map[h], t2.handle_map[h])
            if !(t isa EmptyType)
                handle_map[h] = t
            end
        end
    end
    ExportType(:union, intersect(t1.row, t2.row), handle_map)
end

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
    fields = OrderedDict{Symbol, AbstractSQLType}()
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

function Base.union(t1::ExportType, t2::ExportType)
    handle_map = Dict{Int, RowType}()
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
    ExportType(t1.name, union(t1.row, t2.row), handle_map)
end


