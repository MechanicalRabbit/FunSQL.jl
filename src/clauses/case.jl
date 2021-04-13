# CASE expression.

mutable struct CaseClause <: AbstractSQLClause
    args::Vector{SQLClause}

    CaseClause(; args) =
        new(args)
end

CaseClause(arg1, arg2, args...) =
    CaseClause(args = SQLClause[arg1, arg2, args...])

"""
    CASE(; args)
    CASE(args...)

A `CASE` expression.

# Examples

```jldoctest
julia> c = CASE(OP("<", :year_of_birth, 1970), "boomer", "millenial");

julia> print(render(c))
(CASE WHEN ("year_of_birth" < 1970) THEN 'boomer' ELSE 'millenial' END)
```
"""
CASE(args...; kws...) =
    CaseClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(CASE), pats::Vector{Any}) =
    dissect(scr, CaseClause, pats)

function PrettyPrinting.quoteof(c::CaseClause, qctx::SQLClauseQuoteContext)
    ex = Expr(:call, nameof(CASE))
    if length(c.args) < 2
        push!(ex.args, Expr(:kw, :args, Expr(:vect, quoteof(c.args, qctx)...)))
    else
        append!(ex.args, quoteof(c.args, qctx))
    end
    ex
end

