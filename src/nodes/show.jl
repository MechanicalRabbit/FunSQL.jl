# Show/Hide nodes

mutable struct ShowNode <: TabularNode
    names::Vector{Symbol}
    visible::Bool
    label_map::FunSQL.OrderedDict{Symbol, Int}

    function ShowNode(; names = [], visible = true, label_map = nothing)
        if label_map !== nothing
            new(names, visible, label_map)
        else
            n = new(names, visible, FunSQL.OrderedDict{Symbol, Int}())
            for (i, name) in enumerate(n.names)
                if name in keys(n.label_map)
                    err = FunSQL.DuplicateLabelError(name, path = SQLQuery[n])
                    throw(err)
                end
                n.label_map[name] = i
            end
            n
        end
    end
end

ShowNode(names...; visible = true) =
    ShowNode(names = Symbol[names...], visible = visible)

const Show = SQLQueryCtor{ShowNode}(:Show)

Hide(args...; kws...) =
    Show(args...; kws..., visible = false)

const funsql_show = Show
const funsql_hide = Hide

function FunSQL.PrettyPrinting.quoteof(n::ShowNode, ctx::QuoteContext)
    Expr(:call, n.visible ? :Show : :Hide, quoteof(n.names, ctx)...)
end
