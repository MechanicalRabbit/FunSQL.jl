#!/usr/bin/env julia

using Documenter, NarrativeTest, Test
using FunSQL

if isempty(ARGS)

    @testset "FunSQL" begin

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

    doctest(FunSQL)

    NarrativeTest.testset()

    end

else
    NarrativeTest.testset(ARGS)
end
