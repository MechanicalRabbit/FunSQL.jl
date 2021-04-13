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
                As, From, Fun, Get, Highlight, Select, Where,
                AS, CASE, FROM, FUN, ID, KW, LIT, OP, SELECT, WHERE,
                render
            using Dates
        end)
    with_logger(Logging.ConsoleLogger(stderr, Logging.Warn)) do
        doctest(FunSQL)
    end

    @info "Running narrative tests..."
    NarrativeTest.testset()

    end

else
    NarrativeTest.testset(ARGS)
end
