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

[![FunSQL | JuliaCon 2021][juliacon2021-img]][juliacon2021-url]


## Example

The guiding principle of FunSQL is to allow SQL queries to be constructed from
components created independently and assembled together on the fly.  In
particular, FunSQL notation does not rely on macros or bound variables as they
hinder modular query construction.

To demonstrate a query built with FunSQL, let us consider a question:

*When was the last time each person born between 1930 and 1940 and living in
Illinois was seen by a healthcare provider?*

With FunSQL, it is expressed as a composite `SQLNode` object:

```julia
From(person) |>
Where(Fun.and(Get.year_of_birth .>= 1930,
              Get.year_of_birth .<= 1940)) |>
Join(:location => From(location) |>
                  Where(Get.state .== "IL"),
     on = Get.location_id .== Get.location.location_id) |>
Join(:visit_group => From(visit_occurrence) |>
                     Group(Get.person_id),
     on = Get.person_id .== Get.visit_group.person_id,
     left = true) |>
Select(Get.person_id,
       :max_visit_start_date =>
           Get.visit_group |> Agg.max(Get.visit_start_date))
```

This object is rendered by FunSQL into the following `SELECT` statement:

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

From this example, you could infer that SQL clauses, such as `FROM`, `WHERE`,
and `JOIN`, are represented by the respective `SQLNode` constructors `From`,
`Where`, and `Join`, which are connected together using the pipe (`|>`)
operator.  Note the absence of a `SQLNode` counterpart to nested `SELECT`
clauses; when necessary, FunSQL automatically adds nested subqueries and
threads through them column references and aggregate expressions.

Scalar expressions are straightforward.  `Fun.and`, `.>=` and such are examples
of how FunSQL represents SQL functions and operators; `Agg.max` is a separate
notation for aggregate functions; `Get.person_id` is a reference to a column.
`Get.location.person_id` refers to a column fenced by `:location =>`.

Variables `person`, `location`, and `visit_occurrence` are `SQLTable` objects
describing the corresponding tables.  For the description of this database and
more examples, see the [Tutorial][tutorial-url].


## Supported Features

The following capabilities of SQL are in scope of FunSQL.

- [x] Data retrieval (`SELECT`).
- [ ] Data manipulation (`INSERT`, `UPDATE`, `DELETE`).
- [ ] Data definition (`CREATE TABLE`).

FunSQL generates SQL queries, but does not interact with the database directly.
For this reason, the following features are out of scope of FunSQL.  However,
they may be provided by a separate library built on top of FunSQL.

- [ ] Database introspection.
- [ ] Database migrations.
- [ ] ORM.

Currently, FunSQL is aware of the following SQL dialects:

- `:postgresql`.
- `:sqlite`.
- `:mysql`.
- `:sqlserver`.

This includes dialect-specific serialization of identifiers, literal values,
query parameters, and certain SQL clauses.

FunSQL performs a limited form of query validation.  It verifies that column
references are valid and could be resolved against the corresponding `From` or
`Define` clauses.  Similarly, aggregate and window functions are only permitted
in a context of `Group` or `Partition`.  FunSQL does *not* validate invocations
of SQL functions and operators.

Aside from a high-level `SQLNode` interface, FunSQL implements an intermediate
`SQLCLause` interface, which reflects the lexical structure of a SQL query.
This interface can be used for customizing serialization of SQL functions and
operators with irregular syntax.

Here are supported clauses of the `SELECT` statement:

- [x] `SELECT` clause.  Intermediate `SELECT` subqueries are managed by FunSQL
  automatically, but you can specify an intermediate value with `Define()`.

  - [x] `SELECT DISTINCT` (use `Group` without aggregates).
  - [ ] `SELECT DISTINCT ON` (PostgreSQL-specific, but could be
    emulated using window functions).
  - [ ] `SELECT TOP N PERCENT` (MS SQL Server-specific, but could be
    emulated using window functions).
  - [ ] Other hints and extensions to the `SELECT` clause (`FOR UPDATE`, etc).

- [x] `FROM` clause.  `FROM <table>` and `FROM <schema>.<table>` syntax is
  supported.  `FROM (<subquery>)` is created automatically, when necessary.

  - [ ] `FROM <function>`, e.g., `FROM generate_series(10)` in PostgreSQL.
  - [ ] `TABLESAMPLE`.
  - [ ] Other dialect-specific extensions.

- [x] `JOIN` clause.

  - [x] `LEFT JOIN`, `RIGHT JOIN`, `FULL JOIN`
    (`Join(q, on, left = true, right = true)`).
  - [x] `CROSS JOIN` (`Join(q, on = true)`).
  - [x] `JOIN LATERAL` (use `Bind` and `Var` as if it were a correlated
    subquery).

    - [ ] MS SQL Server-specific syntax `APPLY`.

  - [ ] Automatic join condition inferred from foreign key constraints.

- [x] `WHERE` and `HAVING` clauses; use `Where()`.

- [x] `GROUP BY`.  Use `Group()` without arguments to aggregate over the
  whole dataset.

  - [ ] `ROLLUP`, `CUBE`, `GROUPING SETS`, including emulation.

- [x] `ORDER BY`.

  - [ ] `USING <operator>` (PostgreSQL).
  - [ ] Clarify which operations do not affect the order of the rows
    (`Select`, `Define`, `Limit`, possibly `Where`).
  - [ ] Some dialects do not like `ORDER BY` in subqueries (MS SQL Server).

- [x] `LIMIT` (`OFFSET`, `FETCH`).

- [x] `UNION ALL`; we call it `Append()` to avoid collision with Julia's
      `Union` type constructor.

- [ ] `UNION`, `INTERSECT`, `EXCEPT`.

- [ ] `WITH`.  Using the same (`===`) node in the query expression should
  promote it to a `WITH` subquery.

  - [ ] `WITH` as an alternative SQL rendering strategy, where each tabular
    operation gets its own `WITH` subquery.

- [ ] `WITH RECURSIVE`.  A prototype exists.  The syntax should be `p |>
  Iterate(parent_of(p))` or `p |> Iterate(parent_of(Self()))` to suggest `p |>
  Append(parent_of(p), parent_of(parent_of(p)), ...)`

- [x] Scalar functions and operators.

  - [x] Wrappers are provided for many widely used functions and operators that
    have irregular syntax (`Fun.and`, `Fun.case`, etc).

  - [ ] Validate that the function exists and the argument types are correct.

    - [ ] Normalize the semantics of broadcasted functions (e.g., map `.+` to
      `+` or `DATEADD` depending on the argument types and the target dialect).

- [x] Aggregate functions.

  - [x] `DISTINCT`.
  - [x] `FILTER`.
  - [x] `ORDER BY`.
  - [ ] `WITHIN GROUP`.
  - [ ] Validation is not implemented.

- [x] Window functions.  Use `Partition` to specify the window frame, similar
  to an explicit `WINDOW` clause.

- [x] Table definition including the names of the table and all the columns.

  - [x] Optional schema name.
  - [ ] Column types.
  - [ ] Primary and foreign keys.
  - [ ] More properties to support customizing `CREATE TABLE`.


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
[tutorial-url]: https://mechanicalrabbit.github.io/FunSQL.jl/stable/tutorial/
