# A free-form annotation.

mutable struct NoteClause <: AbstractSQLClause
    over::Union{SQLClause, Nothing}
    text::String
    postfix::Bool

    NoteClause(; over = nothing, text, postfix = false) =
        new(over, text, postfix)
end

NoteClause(text; over = nothing, postfix = false) =
    NoteClause(over = over, text = text, postfix = postfix)

"""
    NOTE(; over = nothing, text, postfix = false)
    NOTE(text; over = nothing, postfix = false)

A free-form prefix of postfix annotation.

# Examples

```jldoctest
julia> c = FROM(:p => :person) |>
           NOTE("TABLESAMPLE SYSTEM (50)", postfix = true) |>
           SELECT((:p, :person_id));

julia> print(render(c))
SELECT "p"."person_id"
FROM "person" AS "p" TABLESAMPLE SYSTEM (50)
```
"""
NOTE(args...; kws...) =
    NoteClause(args...; kws...) |> SQLClause

dissect(scr::Symbol, ::typeof(NOTE), pats::Vector{Any}) =
    dissect(scr, NoteClause, pats)

function PrettyPrinting.quoteof(c::NoteClause, ctx::QuoteContext)
    ex = Expr(:call, nameof(NOTE), quoteof(c.text))
    if c.postfix
        push!(ex.args, Expr(:kw, :postfix, c.postfix))
    end
    if c.over !== nothing
        ex = Expr(:call, :|>, quoteof(c.over, ctx), ex)
    end
    ex
end

rebase(c::NoteClause, c′) =
    NoteClause(over = rebase(c.over, c′), text = c.text, postfix = c.postfix)

