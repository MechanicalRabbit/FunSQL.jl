# SQL operators.

mutable struct OperatorClause <: AbstractSQLClause
    name::Symbol
    args::Vector{SQLClause}

    OperatorClause(;
                   name::Union{Symbol, AbstractString},
                   args) =
        new(Symbol(name), args)
end

OperatorClause(name; args) =
    OperatorClause(name = name, args = args)

OperatorClause(name, args...) =
    OperatorClause(name, args = SQLClause[args...])

"""
    OP(; name, args)
    OP(name; args)
    OP(name, args...)

An application of a SQL operator.

# Examples

```jldoctest
julia> c = OP("NOT", OP("=", :zip, "60614"));

julia> print(render(c))
(NOT ("zip" = '60614'))
```
"""
OP(args...; kws...) =
    OperatorClause(args...; kws...) |> SQLClause

function PrettyPrinting.quoteof(c::OperatorClause; limit::Bool = false, wrap::Bool = false)
    ex = Expr(:call,
              wrap ? nameof(OP) : nameof(OperatorClause),
              string(c.name))
    if !limit
        args_exs = Any[quoteof(arg) for arg in c.args]
        if isempty(c.args)
            push!(ex.args, Expr(:kw, :args, Expr(:vect, args_exs...)))
        else
            append!(ex.args, args_exs)
        end
    else
        push!(ex.args, :…)
    end
    ex
end

function render(ctx, c::OperatorClause)
    if isempty(c.args)
        print(ctx, c.name)
    elseif length(c.args) == 1
        print(ctx, '(', c.name, ' ')
        render(ctx, c.args[1])
        print(ctx, ')')
    else
        render(ctx, c.args, sep = " $(c.name) ")
    end
end

