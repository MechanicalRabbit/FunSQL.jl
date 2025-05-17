# Highlight the nested node.

struct Esc
    val::String
end

Esc(name::Symbol) = Esc(Base.text_colors[name])

Base.show(io::IO, esc::Esc) =
    if get(io, :color, false)
        print(io, esc.val)
    end

struct NormalWrapper
    content::Any
end

PrettyPrinting.tile(w::NormalWrapper) =
    tile_expr(w.content) * literal(Esc(:normal), 0)

PrettyPrinting.tile_expr_or_repr(w::NormalWrapper, pr = -1) =
    PrettyPrinting.tile(w)

struct EscWrapper
    content::Any
    color::Symbol
    restore::Vector{Symbol}
end

function PrettyPrinting.tile(w::EscWrapper)
    lt = literal(Esc(w.color), 0) * tile_expr(w.content)
    for c in w.restore
        lt = lt * literal(Esc(c), 0)
    end
    lt
end

PrettyPrinting.tile_expr_or_repr(w::EscWrapper, pr = -1) =
    PrettyPrinting.tile(w)

struct HighlightNode <: AbstractSQLNode
    color::Symbol

    HighlightNode(;
           color::Union{Symbol, AbstractString}) =
        new(Symbol(color))
end

HighlightNode(color) =
    HighlightNode(color = color)

"""
    Highlight(; color, tail = nothing)
    Highlight(color; tail = nothing)

Highlight `tail` with the given `color`.

The highlighted node is printed with the selected color when the query
containing it is displayed.

Available colors can be found in `Base.text_colors`.

# Examples

```jldoctest
julia> q = From(:person) |>
           Select(Get.person_id |> Highlight(:bold))
let q1 = From(:person),
    q2 = q1 |> Select(Get.person_id)
    q2
end
```
"""
const Highlight = SQLQueryCtor{HighlightNode}(:Highlight)

const funsql_highlight = Highlight

function PrettyPrinting.quoteof(n::HighlightNode, ctx::QuoteContext)
    Expr(:call, :Highlight, quoteof(n.color))
end
