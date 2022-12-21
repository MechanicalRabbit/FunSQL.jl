#!/usr/bin/env julia

using Documenter
using FunSQL

# Highlight indented code blocks as Julia code.
using Documenter.Expanders: ExpanderPipeline, Selectors, Markdown, iscode
abstract type DefaultLanguage <: ExpanderPipeline end
Selectors.order(::Type{DefaultLanguage}) = 99.0
Selectors.matcher(::Type{DefaultLanguage}, node, page, doc) =
    iscode(node, "")
Selectors.runner(::Type{DefaultLanguage}, node, page, doc) =
    page.mapping[node] = Markdown.Code("julia", node.code)

makedocs(
    sitename = "FunSQL.jl",
    format = Documenter.HTML(prettyurls=(get(ENV, "CI", nothing) == "true")),
    pages = [
        "Home" => "index.md",
        "guide/index.md",
        "reference/index.md",
        "examples/index.md",
        "test/index.md",
        "Articles" => [
          "two-kinds-of-sql-query-builders/index.md",
        ],
    ],
    modules = [FunSQL],
    doctest = false
)

deploydocs(
    repo = "github.com/MechanicalRabbit/FunSQL.jl.git",
)
