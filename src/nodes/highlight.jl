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

PrettyPrinting.tile_expr_or_repr(w::EscWrapper, pr = -1) =
    PrettyPrinting.tile(w)

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
Highlight(args...; kws...) =
    HighlightNode(args...; kws...) |> SQLNode

funsql(::Val{:highlight}, args...; kws...) =
    Highlight(args...; kws...)

dissect(scr::Symbol, ::typeof(Highlight), pats::Vector{Any}) =
    dissect(scr, HighlightNode, pats)

function PrettyPrinting.quoteof(n::HighlightNode, ctx::QuoteContext)
    if ctx.limit
        ex = Expr(:call, nameof(Highlight), quoteof(n.color))
        if n.over !== nothing
            ex = Expr(:call, :|>, quoteof(n.over, ctx), ex)
        end
        return ex
    end
    push!(ctx.colors, n.color)
    ex = quoteof(n.over, ctx)
    pop!(ctx.colors)
    EscWrapper(ex, n.color, copy(ctx.colors))
end

label(n::HighlightNode) =
    label(n.over)

rebase(n::HighlightNode, n′) =
    HighlightNode(over = rebase(n.over, n′), color = n.color)
