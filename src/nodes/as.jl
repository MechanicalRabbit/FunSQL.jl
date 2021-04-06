# AS wrapper.

mutable struct AsNode <: AbstractSQLNode
    over::Union{SQLNode, Nothing}
    name::Symbol

    AsNode(;
           over = nothing,
           name::Union{Symbol, AbstractString}) =
        new(over, Symbol(name))
end

AsNode(name; over = nothing) =
    AsNode(over = over, name = name)

"""
    As(; over = nothing; name)
    As(name; over = nothing)
    name => over

An alias for a subquery or an expression.

# Examples

```jldoctest
julia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);

julia> q = From(person) |>
           As(:p) |>
           Select(:birth_year => Get.p.year_of_birth);
```
"""
As(args...; kws...) =
    AsNode(args...; kws...) |> SQLNode

Base.convert(::Type{AbstractSQLNode}, p::Pair{<:Union{Symbol, AbstractString}}) =
    AsNode(name = first(p), over = convert(SQLNode, last(p)))

function PrettyPrinting.quoteof(n::AsNode, qctx::SQLNodeQuoteContext)
    ex = Expr(:call, nameof(As), quoteof(n.name))
    if n.over !== nothing
        ex = Expr(:call, :|>, quoteof(n.over, qctx), ex)
    end
    ex
end

rebase(n::AsNode, n′) =
    AsNode(over = rebase(n.over, n′), name = n.name)

visit(f, n::AsNode) =
    visit(f, n.over)

alias(n::AsNode) =
    n.name

gather!(refs::Vector{SQLNode}, n::AsNode) =
    gather!(refs, n.over)

translate(n::AsNode, subs) =
    translate(n.over, subs)

function split_get(n::SQLNode, stop::Symbol, base::SQLNode)
    core = n[]
    core isa GetNode || return n
    if core.over === nothing
        if core.name === stop
            return base
        else
            return nothing
        end
    end
    over′ = split_get(core.over, stop, base)
    if over′ === nothing
        nothing
    else
        Get(over = over′, name = core.name)
    end
end

function resolve(n::AsNode, req)
    rebases = Dict{SQLNode, SQLNode}()
    base_refs = SQLNode[]
    for ref in req.refs
        !(ref in keys(rebases)) || continue
        core = ref[]
        if core isa GetNode
            ref′ = split_get(ref, n.name, n.over)
            ref′ !== nothing || continue
            if ref′ !== ref
                rebases[ref] = ref′
            end
            push!(base_refs, ref′)
        end
    end
    base_req = ResolveRequest(req.ctx, refs = base_refs)
    base_res = resolve(n.over, base_req)
    repl = Dict{SQLNode, Symbol}()
    for ref in req.refs
        ref′ = get(rebases, ref, ref)
        if ref′ in keys(base_res.repl)
            name = base_res.repl[ref′]
            repl[ref] = name
        end
    end
    ResolveResult(base_res.clause, repl)
end

