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
        elseif pat.head === :(::) && nargs == 1
            :($scr isa $(pat.args[1]))
        elseif pat.head === :(::) && nargs == 2
            ex1 = dissect(scr, pat.args[1])
            ex2 = :($scr isa $(pat.args[2]))
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

function dissect(scr::Symbol, ::Type{Expr}, pats::Vector{Any})
    !isempty(pats) || error("invalid pattern: $(repr(pats))")
    exs = Any[:($scr isa Expr)]
    push!(exs, dissect(:($scr.head), pats[1]))
    minlen = 0
    varlen = false
    for k = 2:lastindex(pats)
        pat = pats[k]
        if pat isa Expr && pat.head === :... && length(pat.args) == 1
            !varlen || error("duplicate vararg pattern: $pat")
            varlen = true
        else
            minlen += 1
        end
    end
    scr_len = gensym(:scr_len)
    if !varlen
        push!(exs, :(local $scr_len = length($scr.args); $scr_len == $minlen))
    else
        push!(exs, :(local $scr_len = length($scr.args); $scr_len >= $minlen))
    end
    seen_vararg = false
    for k = 2:lastindex(pats)
        pat = pats[k]
        l = k - 1
        r = minlen - l + 1
        if pat isa Expr && pat.head === :... && length(pat.args) == 1
            pat = pat.args[1]
            ex = dissect(:($scr.args[$l : $scr_len - $r]), pat)
            seen_vararg = true
        elseif seen_vararg
            ex = dissect(:($scr.args[$scr_len - $r]), pat)
        else
            ex = dissect(:($scr.args[$l]), pat)
        end
        push!(exs, ex)
    end
    Expr(:&&, exs...)
end

function dissect(scr::Symbol, ::Type{QuoteNode}, pats::Vector{Any})
    if length(pats) == 1
        ex = dissect(:($scr.value), pats[1])
        return :($scr isa QuoteNode && $ex)
    end
    error("invalid pattern: $(repr(pats))")
end

function dissect(scr::Symbol, ::Type{GlobalRef}, pats::Vector{Any})
    if length(pats) == 2
        return :($scr isa GlobalRef && $scr.mod == $(pats[1]) && $scr.name === $(pats[2]))
    end
    error("invalid pattern: $(repr(pats))")
end
