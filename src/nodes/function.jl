# Function and operator calls.

mutable struct FunctionNode <: AbstractSQLNode
    name::Symbol
    args::Vector{SQLNode}

    function FunctionNode(;
                          name::Union{Symbol, AbstractString},
                          args = SQLNode[])
        n = new(Symbol(name), args)
        renameoperators!(n)
        checkarity!(n)
        n
    end
end

# Rename Julia operators to SQL equivalents.
function renameoperators!(n::FunctionNode)
    if n.name === :(==)
        n.name = Symbol("=")
    elseif n.name === :(!=)
        n.name = Symbol("<>")
    elseif n.name === :(||)
        n.name = :or
    elseif n.name === :(&&)
        n.name = :and
    elseif n.name === :(!)
        n.name = :not
    end
end

FunctionNode(name; args = SQLNode[]) =
    FunctionNode(name = name, args = args)

FunctionNode(name, args...) =
    FunctionNode(name = name, args = SQLNode[args...])

"""
    Fun(; name, args = [])
    Fun(name; args = [])
    Fun(name, args...)
    Fun.name(args...)

Application of a SQL function or a SQL operator.

A `Fun` node is also generated by broadcasting on `SQLNode` objects.
Names of Julia operators (`==`, `!=`, `&&`, `||`, `!`) are replaced with
their SQL equivalents (`=`, `<>`, `and`, `or`, `not`).

If `name` contains only symbols, or if `name` starts or ends with a space,
the `Fun` node is translated to a SQL operator.

If `name` contains one or more `?` characters, it serves as a template of
a SQL expression where `?` symbols are replaced with the given arguments.
Use `??` to represent a literal `?` mark.  Wrap the template in parentheses
if this is necessary to make the SQL expression unambiguous.

Certain names have a customized translation in order to generate common SQL
functions and operators with irregular syntax:

| `Fun` node                    | SQL syntax                                |
|:----------------------------- |:------------------------------------------|
| `Fun.and(p₁, p₂, …)`          | `p₁ AND p₂ AND …`                         |
| `Fun.between(x, y, z)`        | `x BETWEEN y AND z`                       |
| `Fun.case(p, x, …)`           | `CASE WHEN p THEN x … END`                |
| `Fun.cast(x, "TYPE")`         | `CAST(x AS TYPE)`                         |
| `Fun.concat(s₁, s₂, …)`       | dialect-specific, e.g., `(s₁ \\|\\| s₂ \\|\\| …)` |
| `Fun.current_date()`          | `CURRENT_DATE`                            |
| `Fun.current_timestamp()`     | `CURRENT_TIMESTAMP`                       |
| `Fun.exists(q)`               | `EXISTS q`                                |
| `Fun.extract("FIELD", x)`     | `EXTRACT(FIELD FROM x)`                   |
| `Fun.in(x, q)`                | `x IN q`                                  |
| `Fun.in(x, y₁, y₂, …)`        | `x IN (y₁, y₂, …)`                        |
| `Fun.is_not_null(x)`          | `x IS NOT NULL`                           |
| `Fun.is_null(x)`              | `x IS NULL`                               |
| `Fun.like(x, y)`              | `x LIKE y`                                |
| `Fun.not(p)`                  | `NOT p`                                   |
| `Fun.not_between(x, y, z)`    | `x NOT BETWEEN y AND z`                   |
| `Fun.not_exists(q)`           | `NOT EXISTS q`                            |
| `Fun.not_in(x, q)`            | `x NOT IN q`                              |
| `Fun.not_in(x, y₁, y₂, …)`    | `x NOT IN (y₁, y₂, …)`                    |
| `Fun.not_like(x, y)`          | `x NOT LIKE y`                            |
| `Fun.or(p₁, p₂, …)`           | `p₁ OR p₂ OR …`                           |

# Examples

*Replace missing values with N/A.*

```jldoctest
julia> location = SQLTable(:location, columns = [:location_id, :city]);

julia> q = From(:location) |>
           Select(Fun.coalesce(Get.city, "N/A"));

julia> print(render(q, tables = [location]))
SELECT coalesce("location_1"."city", 'N/A') AS "coalesce"
FROM "location" AS "location_1"
```

*Find patients not born in 1980.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Where(Get.year_of_birth .!= 1980);

julia> print(render(q, tables = [person]))
SELECT
  "person_1"."person_id",
  "person_1"."year_of_birth"
FROM "person" AS "person_1"
WHERE ("person_1"."year_of_birth" <> 1980)
```

*For each patient, show their age in 2000.*

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(:person) |>
           Select(Fun."-"(2000, Get.year_of_birth));

julia> print(render(q, tables = [person]))
SELECT (2000 - "person_1"."year_of_birth") AS "_"
FROM "person" AS "person_1"
```

*Find invalid zip codes.*

```jldoctest
julia> location = SQLTable(:location, columns = [:location_id, :zip]);

julia> q = From(:location) |>
           Select(Fun." NOT SIMILAR TO '[0-9]{5}'"(Get.zip));

julia> print(render(q, tables = [location]))
SELECT ("location_1"."zip" NOT SIMILAR TO '[0-9]{5}') AS "_"
FROM "location" AS "location_1"
```

*Extract the first 3 digits of the zip code.*

```jldoctest
julia> location = SQLTable(:location, columns = [:location_id, :zip]);

julia> q = From(:location) |>
           Select(Fun."SUBSTRING(? FROM ? FOR ?)"(Get.zip, 1, 3));

julia> print(render(q, tables = [location]))
SELECT SUBSTRING("location_1"."zip" FROM 1 FOR 3) AS "_"
FROM "location" AS "location_1"
```
"""
Fun(args...; kws...) =
    FunctionNode(args...; kws...) |> SQLNode

const funsql_fun = Fun

dissect(scr::Symbol, ::typeof(Fun), pats::Vector{Any}) =
    dissect(scr, FunctionNode, pats)

transliterate(::typeof(Fun), name::Symbol, ctx::TransliterateContext, @nospecialize(args...)) =
    Fun(name, args = [transliterate(SQLNode, arg, ctx) for arg in args])

PrettyPrinting.quoteof(n::FunctionNode, ctx::QuoteContext) =
    Expr(:call,
         Expr(:., nameof(Fun),
                  QuoteNode(Base.isidentifier(n.name) ? n.name : string(n.name))),
         quoteof(n.args, ctx)...)

label(n::FunctionNode) =
    Meta.isidentifier(n.name) ? n.name : :_


# Notation for making function nodes.

struct FunClosure
    name::Symbol
end

FunClosure(name::AbstractString) =
    FunClosure(Symbol(name))

Base.show(io::IO, f::FunClosure) =
    print(io, Expr(:., nameof(Fun),
                       QuoteNode(Base.isidentifier(f.name) ? f.name : string(f.name))))

Base.getproperty(::typeof(Fun), name::Symbol) =
    FunClosure(name)

Base.getproperty(::typeof(Fun), name::AbstractString) =
    FunClosure(name)

(f::FunClosure)(args...) =
    Fun(f.name, args = SQLNode[args...])

(f::FunClosure)(; args = SQLNode[]) =
    Fun(f.name, args = args)


# Common SQL functions and operators.

const var"funsql_&&" = FunClosure(:and)
const var"funsql_||" = FunClosure(:or)
const var"funsql_!" = FunClosure(:not)
const var"funsql_==" = FunClosure("=")
const var"funsql_!=" = FunClosure("<>")
const var"funsql_≠" = FunClosure("<>")
const var"funsql_===" = FunClosure(" IS NOT DISTINCT FROM ")
const var"funsql_≡" = FunClosure(" IS NOT DISTINCT FROM ")
const var"funsql_!==" = FunClosure(" IS DISTINCT FROM ")
const var"funsql_≢" = FunClosure(" IS DISTINCT FROM ")
const var"funsql_>" = FunClosure(">")
const var"funsql_>=" = FunClosure(">=")
const var"funsql_≥" = FunClosure(">=")
const var"funsql_<" = FunClosure("<")
const var"funsql_<=" = FunClosure("<=")
const var"funsql_≤" = FunClosure("<=")
const var"funsql_+" = FunClosure("+")
const var"funsql_-" = FunClosure("-")
const var"funsql_*" = FunClosure("*")
const var"funsql_/" = FunClosure("/")
const var"funsql_∈" = FunClosure(:in)
const var"funsql_∉" = FunClosure(:not_in)
const funsql_between = FunClosure(:between)
const funsql_case = FunClosure(:case)
const funsql_cast = FunClosure(:cast)
const funsql_coalesce = FunClosure(:coalesce)
const funsql_concat = FunClosure(:concat)
const funsql_current_date = FunClosure(:current_date)
const funsql_current_timestamp = FunClosure(:current_timestamp)
const funsql_exists = FunClosure(:exists)
const funsql_extract = FunClosure(:extract)
const funsql_in = FunClosure(:in)
const funsql_is_not_null = FunClosure(:is_not_null)
const funsql_is_null = FunClosure(:is_null)
const funsql_like = FunClosure(:like)
const funsql_not_between = FunClosure(:not_between)
const funsql_not_exists = FunClosure(:not_exists)
const funsql_not_in = FunClosure(:not_in)
const funsql_not_like = FunClosure(:not_like)

# Broadcasting notation.

struct FunStyle <: Base.BroadcastStyle
end

Base.BroadcastStyle(::Type{<:AbstractSQLNode}) =
    FunStyle()

Base.BroadcastStyle(::FunStyle, ::Base.Broadcast.DefaultArrayStyle{0}) =
    FunStyle()

Base.broadcastable(n::AbstractSQLNode) =
    n

Base.Broadcast.instantiate(bc::Base.Broadcast.Broadcasted{FunStyle}) =
    bc

Base.copy(bc::Base.Broadcast.Broadcasted{FunStyle}) =
    Fun(nameof(bc.f), args = SQLNode[bc.args...])

Base.convert(::Type{AbstractSQLNode}, bc::Base.Broadcast.Broadcasted{FunStyle}) =
    FunctionNode(nameof(bc.f), args = SQLNode[bc.args...])

# Broadcasting over && and ||.

module DUMMY_CONNECTIVES

function var"&&" end
function var"||" end

end

if VERSION >= v"1.7"
    Base.Broadcast.broadcasted(::Base.Broadcast.AndAnd,
                               arg1::Union{Base.Broadcast.Broadcasted{FunStyle}, AbstractSQLNode},
                               arg2::Union{Base.Broadcast.Broadcasted{FunStyle}, AbstractSQLNode}) =
        Base.Broadcast.broadcasted(DUMMY_CONNECTIVES.var"&&", arg1, arg2)

    Base.Broadcast.broadcasted(::Base.Broadcast.OrOr,
                               arg1::Union{Base.Broadcast.Broadcasted{FunStyle}, AbstractSQLNode},
                               arg2::Union{Base.Broadcast.Broadcasted{FunStyle}, AbstractSQLNode}) =
        Base.Broadcast.broadcasted(DUMMY_CONNECTIVES.var"||", arg1, arg2)
end
