# A free-form annotation.

struct NoteClause <: AbstractSQLClause
    text::String
    postfix::Bool

    NoteClause(; text, postfix = false) =
        new(text, postfix)
end

NoteClause(text; postfix = false) =
    NoteClause(; text, postfix)

"""
    NOTE(; text, postfix = false, tail = nothing)
    NOTE(text; postfix = false, tail = nothing)

A free-form prefix of postfix annotation.

# Examples

```jldoctest
julia> s = FROM(:p => :person) |>
           NOTE("TABLESAMPLE SYSTEM (50)", postfix = true) |>
           SELECT((:p, :person_id));

julia> print(render(s))
SELECT "p"."person_id"
FROM "person" AS "p" TABLESAMPLE SYSTEM (50)
```
"""
const NOTE = SQLSyntaxCtor{NoteClause}

function PrettyPrinting.quoteof(c::NoteClause, ctx::QuoteContext)
    ex = Expr(:call, :NOTE, quoteof(c.text))
    if c.postfix
        push!(ex.args, Expr(:kw, :postfix, c.postfix))
    end
    ex
end
