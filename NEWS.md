# Release Notes


## v0.8.0

* Refactored the SQL translator to make it faster and easier to maintain.
* Improved error messages.
* Include columns added by `Define` to the output.
* Report an error when `Agg` is used without `Group`.
* Deduplicate identical aggregates in a `Group` subquery.
* Support for `WITH` clause.
* Updated the Tutorial/Usage Guide.


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

