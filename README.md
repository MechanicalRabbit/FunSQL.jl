# FunSQL.jl

*FunSQL is a Julia library for compositional construction of SQL queries.*

[![Stable Documentation][docs-rel-img]][docs-rel-url]
[![Development Documentation][docs-dev-img]][docs-dev-url]
[![Zulip Chat][chat-img]][chat-url]
[![Open Issues][issues-img]][issues-url]
[![Build Status][ci-img]][ci-url]
[![Code Coverage Status][codecov-img]][codecov-url]
[![MIT License][license-img]][license-url]


## Overview

Julia programmers sometimes need to interrogate data with the Structured Query
Language (SQL).  But SQL is notoriously hard to write in a modular fashion.

FunSQL exposes full expressive power of SQL with a compositional semantics.
FunSQL allows you to build queries incrementally from small independent
fragments.  This approach is particularly useful for building applications that
programmatically construct SQL queries.

If you want to learn more about FunSQL, watch this video or go straight to the
[FunSQL Tutorial][tutorial-url].

[![FunSQL | JuliaCon 2021][juliacon2021-img]][juliacon2021-url]


## Example

*When was the last time each person born between 1930 and 1940 and living in
Illinois was seen by a healthcare provider?*

With FunSQL, this question is expressed as a composite query object:

```julia
From(person) |>
Where(Fun.and(Get.year_of_birth .>= 1930, Get.year_of_birth .<= 1940)) |>
Join(:location => From(location) |>
                  Where(Get.state .== "IL"),
     on = Get.location_id .== Get.location.location_id) |>
Join(:visit_group => From(visit_occurrence) |>
                     Group(Get.person_id),
     on = Get.person_id .== Get.visit_group.person_id,
     left = true) |>
Select(Get.person_id,
       :max_visit_start_date => Get.visit_group |> Agg.max(Get.visit_start_date))
```

This object is rendered by FunSQL into the following SQL statement:

```sql
SELECT "person_3"."person_id", "visit_group_1"."max" AS "max_visit_start_date"
FROM (
  SELECT "person_1"."location_id", "person_1"."person_id"
  FROM "person" AS "person_1"
  WHERE (("person_1"."year_of_birth" >= 1930) AND ("person_1"."year_of_birth" <= 1940))
) AS "person_3"
JOIN (
  SELECT "location_1"."location_id"
  FROM "location" AS "location_1"
  WHERE ("location_1"."state" = 'IL')
) AS "location_3" ON ("person_3"."location_id" = "location_3"."location_id")
LEFT JOIN (
  SELECT "visit_occurrence_1"."person_id", MAX("visit_occurrence_1"."visit_start_date") AS "max"
  FROM "visit_occurrence" AS "visit_occurrence_1"
  GROUP BY "visit_occurrence_1"."person_id"
) AS "visit_group_1" ON ("person_3"."person_id" = "visit_group_1"."person_id")
```

With FunSQL, SQL clauses such as `FROM`, `WHERE`, and `JOIN` are represented by
invocations of `From`, `Where`, and `Join` connected together using the pipe
(`|>`) operator.  Note the absence of a FunSQL counterpart to nested `SELECT`
clauses; when necessary, FunSQL automatically adds nested subqueries and
threads through them column references and aggregate expressions.

Scalar expressions are straightforward.  `Fun.and`, `.>=` and such are examples
of how FunSQL represents SQL functions and operators; `Agg.max` is a separate
notation for aggregate functions; `Get.person_id` is a reference to a column.
`Get.location.person_id` refers to a column fenced by `:location =>`.

Variables `person`, `location`, and `visit_occurrence` are `SQLTable` objects
describing the corresponding tables.  For the description of this database and
more examples, see the [Tutorial][tutorial-url].

Notably, FunSQL notation does not rely on macros or anonymous functions as they
hinder modular query construction.  FunSQL queries and their intermediate
components are first-class objects that could be constructed independently,
passed around as values, and freely composed together.


[docs-rel-img]: https://img.shields.io/badge/docs-stable-green.svg
[docs-rel-url]: https://mechanicalrabbit.github.io/FunSQL.jl/stable/
[docs-dev-img]: https://img.shields.io/badge/docs-dev-blue.svg
[docs-dev-url]: https://mechanicalrabbit.github.io/FunSQL.jl/dev/
[chat-img]: https://img.shields.io/badge/chat-julia--zulip-blue
[chat-url]: https://julialang.zulipchat.com/#narrow/stream/284102-funsql.2Ejl
[issues-img]: https://img.shields.io/github/issues/MechanicalRabbit/FunSQL.jl.svg
[issues-url]: https://github.com/MechanicalRabbit/FunSQL.jl/issues
[ci-img]: https://github.com/MechanicalRabbit/FunSQL.jl/workflows/CI/badge.svg
[ci-url]: https://github.com/MechanicalRabbit/FunSQL.jl/actions?query=workflow%3ACI+branch%3Amaster
[codecov-img]: https://codecov.io/gh/MechanicalRabbit/FunSQL.jl/branch/master/graph/badge.svg
[codecov-url]: https://codecov.io/gh/MechanicalRabbit/FunSQL.jl
[license-img]: https://img.shields.io/badge/license-MIT-blue.svg
[license-url]: https://raw.githubusercontent.com/MechanicalRabbit/FunSQL.jl/master/LICENSE.md
[juliacon2021-img]: https://img.youtube.com/vi/rGWwmuvRUYk/maxresdefault.jpg
[juliacon2021-url]: https://www.youtube.com/watch?v=rGWwmuvRUYk
[tutorial-url]: https://mechanicalrabbit.github.io/FunSQL.jl/dev/tutorial/
