# Release Notes

## v0.15.0

* **Breaking change:** when a query is used in a scalar context, such as
  an `IN` expression, make it return the first column only (see #75).
  Previously, such query would `SELECT NULL` unless the query ends with
  an explicit `Select()`.


## v0.14.3

* Fix MySQL reflection.  Thanks to Alexander Plavin.


## v0.14.2

* Add DuckDB support.  Thanks to Alexander Plavin.


## v0.14.1

* Fix `Join` incorrectly collapsing an outer branch when it may transform a NULL
  to a non-NULL value.

* Make `@funsql` macro support operators `≥`, `≤`, `≢`, `≡`, `≠`, `∉`, `∈`
  as aliases for `>=`, `<=`, `IS DISTINCT FROM`, `IS NOT DISTINCT FROM`, `<>`,
  `IN`, `NOT IN`, thanks to Ashlin Harris.


## v0.14.0

* `Define`: add parameters `before` and `after` for specifying position
  of the defined columns.

* Introduce the `SQLColumn` type to represent table columns.  The type of
  `SQLTable.columns` is changed from `Vector{Symbol}` to
  `OrderedDict{Symbol, SQLColumn}`.

* Make `SQLTable` an `AbstractDict{Symbol, SQLColumn}`.

* Add DataAPI-compatible metadata to catalog objects `SQLCatalog`, `SQLTable`,
  and `SQLColumn`.

* Add a field `SQLString.columns` with an optional `Vector{SQLColumn}`
  representing output columns of the SQL query.

* Support docstrings in `@funsql` notation.

* Remove support for `const` and variable assignment syntax from `@funsql`
  notation.

* Use a simpler and more consistent rule for collapsing JOIN branches
  (fixes #60).


## v0.13.2

* Wrap a branch of `UNION ALL` in a subquery if it contains `ORDER BY` or
  `LIMIT` clause.


## v0.13.1

* Add support for grouping sets, which are used in SQL to calculate totals
  and subtotals.  The `Group()` node accepts an optional parameter `sets`,
  which is either a grouping mode indicator `:cube` or `:rollup`, or
  a collection of grouping key sets `Vector{Vector{Symbol}}`.  Examples:

  ```julia
  From(:person) |> Group(:year_of_birth, sets = :cube)

  From(:person) |> Group(:year_of_birth, :month_of_birth, sets = :rollup)

  From(:person) |> Group(:year_of_birth, :gender_concept_id,
                         sets = [[:year_of_birth], [:gender_concept_id]])
  ```


## v0.13.0

This release introduces some backward-incompatible changes.  Before upgrading,
please review these notes.

* Type resolution has been refactored to allow assembling query fragments based
  on the type information.

* Type checking is now more strict.  A `Define` field or an optional `Join` will
  be validated even when they are to be elided.

* Resolution of ambiguous column names in `Join` has been changed in favor of
  the *right* branch.  Previously, an ambiguous name would cause an error.

* Node-bound references are no longer supported.  The following query will
  fail:

  ```julia
  qₚ = From(:person)
  qₗ = From(:location)
  q = qₚ |>
      Join(qₗ, on = qₚ.location_id .== qₗ.location_id) |>
      Select(qₚ.person_id, qₗ.state)
  ```

  Use nested references instead:

  ```julia
  q = @funsql begin
      from(person)
      join(
          location => from(location),
          location_id == location.location_id)
      select(person_id, location.state)
  end
  ```


## v0.12.0

This release introduces some backward-incompatible changes.  Before upgrading,
please review these notes.

* The `SQLTable` constructor drops the `schema` parameter.  Instead, it now
  accepts an optional vector of `qualifiers`.
* Bare `Append(p, q)` now produces `p UNION ALL q`.  Previously, bare
  `Append(p, q)` would be interpreted as `Select() |> Append(p, q)`.
* Add Spark dialect.
* Update nodes `Group()` and `Partition()` to accept an optional parameter
  `name`, which speficies the field that holds the group data.
* Add `Over()` node such that `p |> Over(q)` is equivalent to `q |> With(p)`.
* Add the `@funsql` macro, described below.

### `@funsql`

This release introduces `@funsql` macro, which provides a new, concise notation
for building FunSQL queries.  Example:

```julia
using FunSQL

q = @funsql from(person).filter(year_of_birth > 1950).select(person_id)
```

This is equivalent to the following query:

```julia
using FunSQL: From, Get, Select, Where

q = From(:person) |> Where(Get.year_of_birth .> 1950) |> Select(Get.person_id)
```

The `@funsql` notation reduces syntactic noise, making queries prettier and
faster to write.  Semantically, any query that can be constructed with `@funsql`
could also be constructed without the macro, and vice versa.  Moreover, these
two notations could be freely mixed:

```julia
@funsql from(person).$(Where(Get.year_of_birth .> 1950)).select(person_id)

From(:person) |>
@funsql(filter(year_of_birth > 1950)) |>
Select(Get.person_id)
```

In `@funsql` notation, the chain operator (`|>`) is replaced either with
period (`.`) or with block syntax:

```julia
@funsql begin
    from(person)
    filter(year_of_birth > 1950)
    select(person_id)
end
```

Names that are not valid identifiers should be wrapped in backticks:

```julia
@funsql begin
    from(person)
    define(`Patient's age` => 2024 - year_of_birth)
    filter(`Patient's age` >= 16)
end
```

Many SQL functions and operators are available out of the box:

```julia
@funsql from(location).define(city_state => concat(city, ", ", state))

@funsql from(person).filter(year_of_birth < 1900 || year_of_birth > 2024)
```

Comparison chaining is supported:

```julia
@funsql from(person).filter(1950 < year_of_birth < 2000)
```

The `if` statement and the ternary `? :` operator are converted to a `CASE`
expression:

```julia
@funsql begin
    from(person)
    define(
        generation =>
            year_of_birth <= 1964 ? "Baby Boomer" :
            year_of_birth <= 1980 ? "Generation X" :
            "Millenial")
end
```

A `@funsql` query can invoke any SQL function or even an arbitrary scalar
SQL expression:

```julia
@funsql from(location).select(fun(`SUBSTRING(? FROM ? FOR ?)`, zip, 1, 3))
```

Aggregate and window functions are supported:

```julia
@funsql begin
    from(person)
    group()
    select(
        count(),
        min(year_of_birth),
        max(year_of_birth, filter = gender_concept_id == 8507),
        median =>
            agg(`(percentile_cont(0.5) WITHIN GROUP (ORDER BY ?))`, year_of_birth))
end

@funsql begin
    from(visit_occurrence)
    partition(person_id, order_by = [visit_start_date])
    filter(row_number() <= 1)
end
```

Custom scalar and aggregate functions can be integrated to `@funsql` notation:

```julia
const funsql_substring = FunSQL.FunClosure("SUBSTRING(? FROM ? FOR ?)")

@funsql from(location).select(substring(zip, 1, 3))

const funsql_median = FunSQL.AggClosure("(percentile_cont(0.5) WITHIN GROUP (ORDER BY ?))")

@funsql from(person).group().select(median(year_of_birth))
```

In general, any Julia function with a name `funsql_f()` can be invoked as `f()`
within `@funsql` macro.  For example:

```julia
funsql_concept(v, cs...) =
    @funsql from(concept).filter(vocabulary_id == $v && in(concept_id, $cs...))

funsql_ICD10CM(cs...) =
    @funsql concept("ICD10CM", $cs...)
```

For convenience, `@funsql` macro can wrap such function definitions:

```julia
@funsql concept(v, cs...) = begin
    from(concept)
    filter(vocabulary_id == $v && in(concept_id, $cs...))
end

@funsql ICD10CM(cs...) =
    concept("ICD10CM", $cs...)
```

Or even:

```julia
@funsql begin

concept(v, cs...) = begin
    from(concept)
    filter(vocabulary_id == $v && in(concept_id, $cs...))
end

ICD10CM(cs...) =
    concept("ICD10CM", $cs...)

end
```

Here are some other SQL features expressed in `@funsql` notation.  `JOIN` and
`GROUP BY`:

```julia
@funsql begin
    from(person)
    filter(between(year_of_birth, 1930, 1940))
    join(
        location => from(location).filter(state == "IL"),
        on = location_id == location.location_id)
    left_join(
        visit_group => begin
            from(visit_occurrence)
            group(person_id)
        end,
        on = person_id == visit_group.person_id)
    select(
        person_id,
        latest_visit_date => visit_group.max(visit_start_date))
end
```

`ORDER BY` and `LIMIT`:

```julia
@funsql from(person).order(year_of_birth.desc()).limit(10)
```

`UNION ALL`:

```julia
@funsql begin
    append(
        from(measurement).define(date => measurement_date),
        from(observation).define(date => observation_date))
end
```

Recursive queries:

```julia
@funsql begin
    define(n => 1, f => 1)
    iterate(define(n => n + 1, f => f * (n + 1)).filter(n <= 10))
end
```

Query parameters:

```julia
@funsql from(person).filter(year_of_birth >= :THRESHOLD)
```


## v0.11.2

* Fix a number of problems with serializing `Order()` and `Limit()` for
  MS SQL Server.
* Add a column alias to the dummy `NULL` when generating zero-column output.


## v0.11.1

No changes since the last release, enable Zenodo integration.


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
     node.  Use `??` to represent a literal `?` character.  Wrap the template
     in parentheses if this is necessary to make the syntax unambiguous.

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

* Add `Order`, `Asc`, `Desc`.
* Add `Limit`.
* `Fun.in` with a list, `Fun.current_timestamp`.


## v0.6.0

* Add `Append` for creating `UNION ALL` queries.


## v0.5.1

* Support for specifying the window frame.


## v0.5.0

* Add `Define` for calculated columns.
* Correlated subqueries and `JOIN LATERAL` with `Bind`.
* Support for query parameters with `Var`.
* Support for subqueries.
* Add `Partition` and window functions.


## v0.4.0

* Add `Group`.
* Add aggregate expressions.
* Collapse `WHERE` that follows `GROUP` to `HAVING`.
* Add `LeftJoin` alias for `Join(..., left = true)`.


## v0.3.0

* Add `Join`.


## v0.2.0

* Flatten nested SQL subqueries.
* Broadcasting syntax for SQL functions.
* Special `Fun.<name>` notation for SQL functions.
* Support for irregular syntax for functions and operators.
* Outline of the documentation.


## v0.1.1

* Use `let` notation for displaying `SQLNode` objects.
* Add `Highlight` node.
* Highlighting of problematic nodes in error messages.


## v0.1.0

* Initial release.
* `From`, `Select`, and `Where` are implemented.
