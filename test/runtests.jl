#!/usr/bin/env julia

using Documenter, Logging, NarrativeTest, Test
using FunSQL

# Suppress deprecation warnings on the use of `kwargs.data` in DBInterface.
if VERSION >= v"1.7-DEV"
    Base.getproperty(x::Base.Pairs, s::Symbol) =
        getfield(x, s)
end

if isempty(ARGS)

    @testset "FunSQL" begin

    @info "Running doctests..."
    DocMeta.setdocmeta!(
        FunSQL,
        :DocTestSetup,
        quote
            using FunSQL:
                SQLTable,
                Agg, Append, As, Bind, Define, From, Fun, Get, Group,
                Highlight, Join, LeftJoin, Partition, Select, Var, Where,
                AGG, AS, CASE, FROM, FUN, GROUP, HAVING, ID, JOIN, KW, LIMIT,
                LIT, OP, PARTITION, SELECT, UNION, VAR, WHERE, WINDOW,
                render
            using Dates
        end)
    with_logger(Logging.ConsoleLogger(stderr, Logging.Warn)) do
        doctest(FunSQL)
    end

    @info "Running narrative tests..."
    NarrativeTest.testset(joinpath(@__DIR__, "../docs/src"))

    end

else
    NarrativeTest.testset(ARGS)
end
