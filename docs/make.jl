#!/usr/bin/env julia

using Documenter
using FunSQL

# Highlight indented code blocks as Julia code.
using Documenter: Expanders, Selectors, MarkdownAST, iscode
abstract type DefaultLanguage <: Expanders.ExpanderPipeline end
Selectors.order(::Type{DefaultLanguage}) = 99.0
Selectors.matcher(::Type{DefaultLanguage}, node, page, doc) =
    iscode(node, "")
Selectors.runner(::Type{DefaultLanguage}, node, page, doc) =
    node.element = MarkdownAST.CodeBlock("julia", node.element.code)

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
    doctest = false,
    repo = Remotes.GitHub("MechanicalRabbit", "FunSQL.jl"),
)

deploydocs(
    repo = "github.com/MechanicalRabbit/FunSQL.jl.git",
)
