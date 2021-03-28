# Semantic structure of a SQL query.


# Base node type.

"""
A SQL operation.
"""
abstract type AbstractSQLNode
end

Base.show(io::IO, n::AbstractSQLNode) =
    print(io, quoteof(n, limit = true))

Base.show(io::IO, ::MIME"text/plain", n::AbstractSQLNode) =
    pprint(io, n)


# Specialization barrier node.

"""
An opaque wrapper over an arbitrary SQL node.
"""
struct SQLNode <: AbstractSQLNode
    content::AbstractSQLNode

    SQLNode(@nospecialize content::AbstractSQLNode) =
        new(content)
end

Base.getindex(n::SQLNode) =
    getfield(n, :content)

Base.convert(::Type{SQLNode}, n::SQLNode) =
    n

Base.convert(::Type{SQLNode}, @nospecialize n::AbstractSQLNode) =
    SQLNode(n)

Base.convert(::Type{SQLNode}, obj) =
    convert(SQLNode, convert(AbstractSQLNode, obj)::AbstractSQLNode)

PrettyPrinting.quoteof(n::SQLNode; limit::Bool = false, wrap::Bool = false) =
    quoteof(n[], limit = limit, wrap = true)

(n::AbstractSQLNode)(n′) =
    n(convert(SQLNode, n′))

(n::AbstractSQLNode)(n′::SQLNode) =
    rebase(n, n′)

rebase(n::SQLNode, n′) =
    convert(SQLNode, rebase(n[], n′))


# Concrete node types.

include("nodes/as.jl")
include("nodes/from.jl")
include("nodes/get.jl")
include("nodes/literal.jl")
include("nodes/select.jl")
include("nodes/where.jl")

