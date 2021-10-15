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

