#!/usr/bin/env julia

using Documenter, Logging, NarrativeTest, Test
using FunSQL

if isempty(ARGS)

    @testset "FunSQL" begin

    @info "Running doctests..."
    DocMeta.setdocmeta!(
        FunSQL,
        :DocTestSetup,
        quote
            using FunSQL:
                SQLTable,
                Agg, As, Bind, Define, From, Fun, Get, Group, Highlight, Join,
                LeftJoin, Partition, Select, Var, Where,
                AGG, AS, CASE, FROM, FUN, GROUP, HAVING, ID, JOIN, KW, LIT, OP,
                PARTITION, SELECT, VAR, WHERE, WINDOW,
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
