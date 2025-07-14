# Hide node

mutable struct HideNode <: TabularNode
    over::Union{SQLNode, Nothing}
    names::Vector{Symbol}
    label_map::FunSQL.OrderedDict{Symbol, Int}

    function HideNode(; over = nothing, names = [], label_map = nothing)
        if label_map !== nothing
            new(over, names, label_map)
        else
            n = new(over, names, FunSQL.OrderedDict{Symbol, Int}())
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

HideNode(names...; over = nothing) =
    HideNode(over = over, names = Symbol[names...])

Hide(args...; kws...) =
    HideNode(args...; kws...) |> SQLNode

const funsql_hide = Hide

dissect(scr::Symbol, ::typeof(Hide), pats::Vector{Any}) =
    dissect(scr, HideNode, pats)

function FunSQL.PrettyPrinting.quoteof(n::HideNode, ctx::FunSQL.QuoteContext)
    ex = Expr(:call, nameof(Hide), quoteof(n.names, ctx)...)
    if n.over !== nothing
        ex = Expr(:call, :|>, FunSQL.quoteof(n.over, ctx), ex)
    end
    ex
end
