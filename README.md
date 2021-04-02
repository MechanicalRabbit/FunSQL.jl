# FunSQL.jl

*FunSQL is a Julia library for compositional construction of SQL queries.*

[![Stable Documentation][doc-rel-img]][doc-rel-url]
[![Development Documentation][doc-dev-img]][doc-dev-url]
[![Build Status][ci-img]][ci-url]
[![Code Coverage Status][codecov-img]][codecov-url]
[![Open Issues][issues-img]][issues-url]
[![MIT License][license-img]][license-url]

Julia programmers sometimes need to interrogate data with the Structured Query
Language (SQL). But SQL is notoriously hard to write in a modular fashion.

FunSQL exposes full expressive power of SQL with a compositional semantics.
FunSQL allows you to build queries incrementally from small independent
fragments. This approach is particularly useful for building applications that
programmatically construct SQL queries.

For a fully functional prototype, see the [prototype] branch.


[doc-rel-img]: https://img.shields.io/badge/docs-stable-green.svg
[doc-rel-url]: https://mechanicalrabbit.github.io/FunSQL.jl/stable/
[doc-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[doc-dev-url]: https://mechanicalrabbit.github.io/FunSQL.jl/dev/
[ci-img]: https://github.com/MechanicalRabbit/FunSQL.jl/workflows/CI/badge.svg
[ci-url]: https://github.com/MechanicalRabbit/FunSQL.jl/actions?query=workflow%3ACI+branch%3Amaster
[codecov-img]: https://codecov.io/gh/MechanicalRabbit/FunSQL.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/MechanicalRabbit/FunSQL.jl
[issues-img]: https://img.shields.io/github/issues/MechanicalRabbit/FunSQL.jl.svg
[issues-url]: https://github.com/MechanicalRabbit/FunSQL.jl/issues
[license-img]: https://img.shields.io/badge/license-MIT-blue.svg
[license-url]: https://raw.githubusercontent.com/MechanicalRabbit/FunSQL.jl/master/LICENSE.md
[prototype]: https://github.com/MechanicalRabbit/FunSQL.jl/tree/prototype
