#!/usr/bin/env julia

using Documenter
using FunSQL

# Setup for doctests.
DocMeta.setdocmeta!(
    FunSQL,
    :DocTestSetup,
    quote
        using FunSQL:
            SQLTable,
            As, Call, From, Get, Highlight, Select, Where,
            AS, FROM, ID, LIT, OP, SELECT, WHERE,
            render
        using Dates
    end)

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
    ],
    modules = [FunSQL]
)

deploydocs(
    repo = "github.com/MechanicalRabbit/FunSQL.jl.git",
)