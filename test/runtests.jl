#!/usr/bin/env julia

using Documenter, Logging, NarrativeTest, Test
using FunSQL

ENV["LINES"] = "24"
ENV["COLUMNS"] = "80"

if isempty(ARGS)

    @testset "FunSQL" begin

    @info "Running doctests..."
    DocMeta.setdocmeta!(
        FunSQL,
        :DocTestSetup,
        quote
            using FunSQL:
                SQLTable,
                Agg, Append, As, Asc, Bind, Define, Desc, From, Fun, Get,
                Group, Highlight, Iterate, Join, LeftJoin, Limit, Order,
                Partition, Select, Sort, Var, Where, With, WithExternal,
                AGG, AS, ASC, CASE, CTE, DESC, FROM, FUN, GROUP, HAVING, ID, JOIN,
                KW, LIMIT, LIT, OP, ORDER, PARTITION, SELECT, SORT, UNION, VAR,
                WHERE, WINDOW, WITH,
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
