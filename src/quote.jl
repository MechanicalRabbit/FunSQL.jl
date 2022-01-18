# Converting composite objects to Expr nodes for pretty printing.

struct QuoteContext
    limit::Bool
    vars::IdDict{Any, Symbol}
    colors::Vector{Symbol}

    QuoteContext(;
                 limit = false,
                 vars = IdDict{Any, Symbol}(),
                 colors = [:normal]) =
        new(limit, vars, colors)
end

# Compact representation of a column table.

function PrettyPrinting.quoteof(columns::NamedTuple, ctx::QuoteContext)
    if !ctx.limit
        ex = Expr(:tuple)
        for (k, v) in pairs(columns)
            if v isa Vector
                vex = Expr(:vect)
                if length(v) >= 1
                    push!(vex.args, quoteof(v[1]))
                end
                if length(v) > 1
                    push!(vex.args, :…)
                end
            else
                vex = quoteof(v)
            end
            push!(ex.args, Expr(:(=), k, vex))
        end
        ex
    else
        :…
    end
end

