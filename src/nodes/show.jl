# Show/Hide nodes

mutable struct ShowNode <: TabularNode
    over::Union{SQLNode, Nothing}
    names::Vector{Symbol}
    visible::Bool
    label_map::FunSQL.OrderedDict{Symbol, Int}

    function ShowNode(; over = nothing, names = [], visible = true, label_map = nothing)
        if label_map !== nothing
            new(over, names, visible, label_map)
        else
            n = new(over, names, visible, FunSQL.OrderedDict{Symbol, Int}())
            for (i, name) in enumerate(n.names)
                if name in keys(n.label_map)
                    err = FunSQL.DuplicateLabelError(name, path = [n])
                    throw(err)
                end
                n.label_map[name] = i
            end
            n
        end
    end
end

ShowNode(names...; over = nothing, visible = true) =
    ShowNode(over = over, names = Symbol[names...], visible = visible)

Show(args...; kws...) =
    ShowNode(args...; kws...) |> SQLNode

Hide(args...; kws...) =
    ShowNode(args...; kws..., visible = false) |> SQLNode

const funsql_show = Show
const funsql_hide = Hide

dissect(scr::Symbol, ::typeof(Show), pats::Vector{Any}) =
    dissect(scr, ShowNode, pats)

function FunSQL.PrettyPrinting.quoteof(n::ShowNode, ctx::FunSQL.QuoteContext)
    ex = Expr(:call, nameof(n.visible ? Show : Hide), quoteof(n.names, ctx)...)
    if n.over !== nothing
        ex = Expr(:call, :|>, FunSQL.quoteof(n.over, ctx), ex)
    end
    ex
end
