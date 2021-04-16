# Pattern matching for clauses and nodes.

macro dissect(val, pat)
    esc(dissect(val, pat))
end

function dissect(@nospecialize(val), @nospecialize(pat))
    pat !== :_ || return :(true)
    scr = gensym(:scr)
    ex = dissect(scr, pat)
    :(local $scr = $val; $ex)
end

function dissect(scr::Symbol, @nospecialize(pat))
    if pat isa Symbol
        if pat === :_
            :(true)
        elseif pat === :nothing || pat === :missing
            :($scr === $pat)
        else
            :(local $pat = $scr; true)
        end
    elseif pat isa Bool
        :($scr === $pat)
    elseif pat isa QuoteNode && pat.value isa Symbol
        :($scr === $pat)
    elseif pat isa Expr
        nargs = length(pat.args)
        if pat.head === :(:=) && nargs == 2
            ex1 = dissect(scr, pat.args[1])
            ex2 = dissect(scr, pat.args[2])
            :($ex2 && $ex1)
        elseif pat.head === :&& || pat.head === :||
            Expr(pat.head, Any[dissect(scr, arg) for arg in pat.args]...)
        elseif pat.head === :kw && nargs == 2
            dissect(:($scr.$(pat.args[1])), pat.args[2])
        elseif pat.head === :call && nargs >= 1 &&
                                     (local f = pat.args[1]; f isa Symbol)
            dissect(scr, getfield(FunSQL, f), pat.args[2:end])
        else
            error("invalid pattern: $(repr(pat))")
        end
    else
        error("invalid pattern: $(repr(pat))")
    end
end

function dissect(scr::Symbol, ::typeof(|>), pats::Vector{Any})
    if length(pats) == 2 && (local call = pats[2]; call isa Expr)
        if call.head === :call
            pat = Expr(:call, call.args..., Expr(:kw, :over, pats[1]))
            return dissect(scr, pat)
        elseif call.head === :||
            return Expr(call.head, Any[dissect(scr, Expr(:call, :|>, pats[1], arg))
                                       for arg in call.args]...)
        end
    end
    error("invalid pattern: $(repr(pats))")
end

