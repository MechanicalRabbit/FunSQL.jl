# Highlight the nested node.

struct Esc
    val::String
end

Esc(name::Symbol) = Esc(Base.text_colors[name])

Base.show(io::IO, esc::Esc) =
    if get(io, :color, false)
        print(io, esc.val)
    end

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

mutable struct HighlightNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    color::Symbol

    HighlightNode(;
           over = nothing,
           color::Union{Symbol, AbstractString}) =
        new(over, Symbol(color))
end

HighlightNode(color; over = nothing) =
    HighlightNode(over = over, color = color)

"""
    Highlight(; over = nothing; color)
    Highlight(color; over = nothing)

Highlight `over` with the given `color`.

Available colors can be found in `Base.text_colors`.

# Examples

```jldoctest
julia> q = Get.person_id |> Highlight(:bold);
```
"""
Highlight(args...; kws...) =
    HighlightNode(args...; kws...) |> SQLNode

function PrettyPrinting.quoteof(n::HighlightNode, qctx::SQLNodeQuoteContext)
    if qctx.limit
        ex = Expr(:call, nameof(Highlight), quoteof(n.color))
        if n.over !== nothing
            ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
        end
        return ex
    end
    push!(qctx.colors, n.color)
    ex = quoteof(n.over, qctx)
    pop!(qctx.colors)
    EscWrapper(ex, n.color, copy(qctx.colors))
end

rebase(n::HighlightNode, n′) =
    HighlightNode(over = rebase(n.over, n′), color = n.color)

