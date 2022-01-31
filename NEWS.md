# Release Notes


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

