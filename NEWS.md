# Release Notes


## v0.11.0

This release introduces some backward-incompatible changes.  Before upgrading,
please review these notes.

* The `Iterate()` node, which is used for assembling recursive queries, has
  been simplified.  In the previous version, the argument of `Iterate()` must
  explicitly refer to the output of the previous iteration:

  ```julia
  Base() |>
  Iterate(From(:iteration) |>
          IterationStep() |>
          As(:iteration))
  ```

  In v0.11.0, this query is written as:

  ```julia
  Base() |>
  Iterate(IterationStep())
  ```

  Alternatively, the output of the previous iteration can be fetched with the
  `From(^)` node:

  ```julia
  Base() |>
  Iterate(From(^) |>
          IterationStep())
  ```

* Function nodes with names `Fun."&&"`, `Fun."||"`, and `Fun."!"` are now
  serialized as logical operators `AND`, `OR`, and `NOT`.  Broadcasting
  notation `p .&& q`, `p .|| q`, `.!p` is also supported.

  FunSQL interpretation of `||` conflicts with SQL dialects that use `||`
  to represent string concatenation.  Other dialects use function `concat`.
  In FunSQL, always use `Fun.concat`, which will pick correct serialization
  depending on the target dialect.

* Rendering of `Fun` nodes can now be customized by overriding the method
  `serialize!()`, which is dispatched on the node name.  The following names
  have customized serialization: `and`, `between`, `case`, `cast`, `concat`,
  `current_date`, `current_timestamp`, `exists`, `extract`, `in`,
  `is_not_null`, `is_null`, `like`, `not`, `not_between`, `not_exists`,
  `not_in`, `not_like`, `or`.

* Introduce template notation for representing irregular SQL syntax.
  For example, `Fun."SUBSTRING(? FROM ? FOR ?)"(Get.zip, 1, 3)` generates
  `SUBSTRING("location_1"."zip" FROM 1 to 3)`.

  In general, the name of a `Fun` node is interpreted as a function name,
  an operator name, or a template string:

  1. If the name has a custom `serialize!()` method, it is used for rendering
     the node.  Example: `Fun.in(Get.zip, "60614", "60615")`.

  2. If the name contains a placeholder character `?`, it is interpreted as
     a template.  Placeholders are replaced with the arguments of the `Fun`
     node.  Use `??` to represent a literal `?` character.  The generated SQL
     is wrapped in parentheses unless the template ends with `)`.

  3. If the name contains only symbol characters, or if the name starts or
     ends with a space, it is interpreted as an operator name.  Examples:
     `Fun."-"(2020, Get.year_of_birth)`, `Fun." ILIKE "(Get.city, "Ch%")`,
     `Fun." COLLATE \"C\""(Get.state)`, `Fun."CURRENT_TIME "()`.

  4. Otherwise, the name is interpreted as a function name.  The function
     arguments are separated by a comma and wrapped in parentheses.  Examples:
     `Fun.now()`, `Fun.coalesce(Get.city, "N/A")`.

* `Agg` nodes also support `serialize!()` and template notation.  Custom
  serialization is provided for `Agg.count()` and `Agg.count_distinct(arg)`.

* Remove `distinct` flag from `Agg` nodes.  To represent `COUNT(DISTINCT …)`,
  use `Agg.count_distinct(…)`.  Otherwise, use template notation, e.g.,
  `Agg."string_agg(DISTINCT ?, ? ORDER BY ?)"(Get.state, ",", Get.state)`.

* Function names are no longer automatically converted to upper case.

* Remove ability to customize translation of `Fun` nodes to clause tree
  by overriding the `translate()` method.

* Remove clauses `OP`, `KW`, `CASE`, which were previously used for expressing
  operators and irregular syntax.

* Add support for table-valued functions.  Such functions return tabular data
  and must appear in a `FROM` clause.  Example:

  ```julia
  From(Fun.regexp_matches("2,3,5,7,11", "(\\d+)", "g"),
       columns = [:captures]) |>
  Select(Fun."CAST(?[1] AS INTEGER)"(Get.captures))
  ```

  ```sql
  SELECT CAST("regexp_matches_1"."captures"[1] AS INTEGER) AS "_"
  FROM regexp_matches('2,3,5,7,11', '(\d+)', 'g') AS "regexp_matches_1" ("captures")
  ```

* To prevent duplicating SQL expressions, `Define()` and `Group()` may create
  an additional subquery (#11).  Take, for example:

  ```julia
  From(:person) |>
  Define(:age => 2020 .- Get.year_of_birth) |>
  Where(Get.age .>= 16) |>
  Select(Get.person_id, Get.age)
  ```

  In the previous version, the definition of `age` is replicated in both
  `SELECT` and `WHERE` clauses:

  ```sql
  SELECT
    "person_1"."person_id",
    (2020 - "person_1"."year_of_birth") AS "age"
  FROM "person" AS "person_1"
  WHERE ((2020 - "person_1"."year_of_birth") >= 16)
  ```

  In v0.11.0, `age` is evaluated once in a nested subquery:

  ```sql
  SELECT
    "person_2"."person_id",
    "person_2"."age"
  FROM (
    SELECT
      "person_1"."person_id",
      (2020 - "person_1"."year_of_birth") AS "age"
    FROM "person" AS "person_1"
  ) AS "person_2"
  WHERE ("person_2"."age" >= 16)
  ```

* Similarly, aggregate expressions used in `Bind()` are evaluated in a separate
  subquery (#12).

* Fix a bug where FunSQL fails to generate a correct `SELECT DISTINCT` query
  when key columns of `Group()` are not used by the following nodes.  For
  example, the following query pipeline would fail to render SQL:

```julia
  From(:person) |>
  Group(Get.year_of_birth) |>
  Group() |>
  Select(Agg.count())
  ```

  Now it correctly renders:

  ```sql
  SELECT count(*) AS "count"
  FROM (
    SELECT DISTINCT "person_1"."year_of_birth"
    FROM "person" AS "person_1"
  ) AS "person_2"
  ```

* Article *Two Kinds of SQL Query Builders* is added to documentation.

* Where possible, pretty-printing replaces `Lit` nodes with their values.


## v0.10.2

* Generate aliases for CTE tables (fixes #33).


## v0.10.1

* `From` can take a `DataFrame` or any `Tables.jl`-compatible source.
* More examples.


## v0.10.0

* Add `SQLCatalog` type that encapsulates information about database
  tables, the target SQL dialect, and a cache of rendered queries.
* Add function `reflect` to retrieve information about available
  database tables.
* `From(::Symbol)` can refer to a table in the database catalog.
* Add a dependency on `DBInterface` package.
* Add type `SQLConnection <: DBInterface.Connection` that combines
  a raw database connection and the database catalog. Also add
  `SQLStatement <: DBInterface.Statement`.
* Implement `DBInterface.connect` to create a database connection
  and call `reflect` to retrieve the database catalog.
* Implement `DBInterface.prepare` and `DBInterface.execute` to
  render a query node to SQL and immediately compile or execute it.
* Allow `render` to take a `SQLConnection` or a `SQLCatalog` argument.
* Rename `SQLStatement` to `SQLString`, drop the `dialect` field.
* Update the guide and the examples to use the DBInterface API
  and improve many docstrings.


## v0.9.2

* Compatibility with PrettyPrinting 0.4.


## v0.9.1

* `Join`: add `optional` flag to omit the `JOIN` clause in the case when
  the data from the right branch is not used by the query.
* `With`: add `materialized` flag to make CTEs with `MATERIALIZED` and
  `NOT MATERIALIZED` annotations.
* Add `WithExternal` node that can be used to prepare the definition for
  a `CREATE TABLE AS` or a `SELECT INTO` statement.
* Rearranging clause types: drop `CTE` clause; add `columns` to `AS` clause;
  add `NOTE` clause.


## v0.9.0

* Add `Iterate` node for making recursive queries.
* Add `With` and `From(::Symbol)` nodes for assigning a name to an intermediate
  dataset.
* `From(nothing)` for making a unit dataset.
* Rename `Select.list`, `Append.list`, etc to `args`.
* More documentation updates.


## v0.8.2

* Require Julia ≥ 1.6.
* Render each argument on a separate line for `SELECT`, `GROUP BY`, `ORDER BY`,
  as well as for a top-level `AND` in `WHERE` and `HAVING`.
* Improve `SQLDialect` interface.
* Add Jacob's `CASE` example.


## v0.8.1

* Update documentation and examples.
* Fix quoting of MySQL identifiers.


## v0.8.0

* Refactor the SQL translator to make it faster and easier to maintain.
* Improve error messages.
* Include columns added by `Define` to the output.
* Report an error when `Agg` is used without `Group`.
* Deduplicate identical aggregates in a `Group` subquery.
* Support for `WITH` clause.
* Update the Tutorial/Usage Guide.


## v0.7.0

- Add `Order`, `Asc`, `Desc`.
- Add `Limit`.
- `Fun.in` with a list, `Fun.current_timestamp`.


## v0.6.0

- Add `Append` for creating `UNION ALL` queries.


## v0.5.1

- Support for specifying the window frame.


## v0.5.0

- Add `Define` for calculated columns.
- Correlated subqueries and `JOIN LATERAL` with `Bind`.
- Support for query parameters with `Var`.
- Support for subqueries.
- Add `Partition` and window functions.


## v0.4.0

- Add `Group`.
- Add aggregate expressions.
- Collapse `WHERE` that follows `GROUP` to `HAVING`.
- Add `LeftJoin` alias for `Join(..., left = true)`.


## v0.3.0

-  Add `Join`.


## v0.2.0

- Flatten nested SQL subqueries.
- Broadcasting syntax for SQL functions.
- Special `Fun.<name>` notation for SQL functions.
- Support for irregular syntax for functions and operators.
- Outline of the documentation.


## v0.1.1

- Use `let` notation for displaying `SQLNode` objects.
- Add `Highlight` node.
- Highlighting of problematic nodes in error messages.


## v0.1.0

- Initial release.
- `From`, `Select`, and `Where` are implemented.
