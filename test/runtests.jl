#!/usr/bin/env julia

using Documenter, Logging, NarrativeTest, Test
using FunSQL

ENV["LINES"] = "24"
ENV["COLUMNS"] = "80"

# Ignore the difference in the output of `print(Int)` between 32-bit and 64-bit platforms.
subs = NarrativeTest.common_subs()
push!(subs, r"Int64" => s"Int(32|64)")

if isempty(ARGS)

    @testset "FunSQL" begin

    @info "Running doctests..."
    DocMeta.setdocmeta!(
        FunSQL,
        :DocTestSetup,
        quote
            using FunSQL:
                SQLString, pack,
                SQLDialect,
                SQLTable, SQLCatalog,
                Agg, Append, As, Asc, Bind, Define, Desc, From, Fun, Get,
                Group, Highlight, Iterate, Join, LeftJoin, Limit, Order, Over,
                Partition, Select, Sort, Var, Where, With, WithExternal,
                AGG, AS, ASC, DESC, FROM, FUN, GROUP, HAVING, ID, JOIN, LIMIT,
                LIT, NOTE, ORDER, PARTITION, SELECT, SORT, UNION, VALUES, VAR,
                WHERE, WINDOW, WITH,
                render
            using Dates
            using DataFrames: DataFrame
        end)
    with_logger(Logging.ConsoleLogger(stderr, Logging.Warn)) do
        doctest(FunSQL)
    end

    @info "Running narrative tests..."
    NarrativeTest.testset(joinpath(@__DIR__, "../docs/src"), subs = subs)

    end

else
    NarrativeTest.testset(ARGS, subs = subs)
end
