# Two Kinds of SQL Query Builders

The SQL language has a paradoxical fate.  Although it was deliberately designed
to appeal to a human user, nowadays most of SQL code is written—or rather
generated—by the computer.  Many computer programs need to query some database,
and, for the vast majority of database servers, SQL is the only supported query
language.  But generating SQL is not an easy task because of the complicated
and obscure rules of its quasi-English grammar (the original name SEQUEL stands
for Structured *English* Query Language).  For this reason, programs that
interact with a database often use specialized libraries for generating SQL
queries.

One of such libraries is FunSQL.  FunSQL is designed with two goals in mind:
supporting the full range of SQL's querying capabilities and exposing these
capabilities in a compositional, data-oriented interface.  This makes FunSQL
the best tool for data analysis in SQL and differentiates it from all the other
query building libraries.

And yet the difference between FunSQL and other query builders is not
immediately apparent.  In fact, the interfaces of various query building
libraries seem almost identical.  A query that finds *100 oldest male patients*
(in the [OMOP CDM](https://ohdsi.github.io/CommonDataModel/cdm53.html)
database) is assembled with FunSQL as follows:
```julia
From(:person) |>
Where(Get.gender_concept_id .== 8507) |>
Order(Get.year_of_birth) |>
Limit(100) |>
Select(Get.person_id)
```
The same query can be written in Ruby using [Active Record Query
Interface](https://guides.rubyonrails.org/active_record_querying.html):
```ruby
Person
.where("gender_concept_id = ?", 8507)
.order(:year_of_birth)
.limit(100)
.select(:person_id)
```
Or in PHP with [Laravel's Query Builder](https://laravel.com/docs/9.x/queries):
```php
DB::table('person')
->where('gender_concept_id', '=', 8507)
->orderBy('year_of_birth')
->limit(100)
->select('person_id')
```
In C#'s [EF/LINQ](https://docs.microsoft.com/en-us/ef/core/querying/):
```csharp
Person
.Where(p => p.gender_concept_id == 8507)
.OrderBy(p => p.year_of_birth)
.Take(100)
.Select(p => new { person_id = p.person_id });
```
Or in R with [dbplyr](https://dbplyr.tidyverse.org/):
```r
tbl(conn, "person") %>%
filter(gender_concept_id == 8507) %>%
arrange(year_of_birth) %>%
head(100) %>%
select(person_id)
```
In each of these code samples, the query is assembled using essentially the
same interface.  Stripped of its syntactic shell, the process of assembling the
query can be visualized as a diagram of five processing nodes connected in a
pipeline:

*Diagram*

It is precisely the fact that the query is progressively assembled using
atomic, independent components that lets us call this interface
*compositional*.

However we did claim that FunSQL differs from all the other query building
libraries, and now apparently proved the opposite?  As a matter of fact, they
*are* different, even if this difference is not reflected in notation.  To
demonstrate this, let us rearrange this pipeline, moving the `Order` and
`Limit` nodes in front of `Where`.

*Diagram*

How does this rearrangement affect the output of the query?  The answer depends
on the library.  With FunSQL, as well as EF/LINQ and dbplyr, it changes the
output from *100 oldest male patients* to *the males among 100 oldest
patients*.  But not so with the other two libraries, Active Record and Laravel,
where rearranging the pipeline has *no* effect on the output.

To summarize, the following query builders are sensitive to the order of the
pipeline nodes:

- FunSQL
- EF/LINQ
- dbplyr

And the following are not:

- Active Record
- Laravel

These are the two kinds of query builders from this article's title.  But how
can these libraries act so differently while sharing the same interface?  To
answer this question, we need to focus on what is only implicitly present on
the pipeline diagram: the information that is processed by the pipeline nodes.

*Diagram*

A node with one incoming and one outgoing arrow symbolizes a processing unit
that takes the input data, transforms it, and emits the output data.  While the
character of the data is not revealed, it is tempting to assume it to be the
tabular data extracted from the database.

*Diagram*

But this can't be right, at least not literally, because the SQL query builder
cannot read from the database directly.  What it could do is to generate such a
SQL query that would produce the same output as the pipeline on the diagram
would:
```sql
SELECT "person_1"."person_id"
FROM "person" AS "person_1"
WHERE ("person_1"."gender_concept_id" = 8507)
ORDER BY "person_1"."year_of_birth"
LIMIT 100
```
In other words, the pipeline serves as a specification for the SQL query.  And
indeed, this is how FunSQL and the other two libraries, EF/LINQ and dbplyr,
operate.  We can call such query builders *data-oriented*.

The conversion of the pipeline to SQL is not always that straightforward.  Even
though we could freely reorder the nodes in a pipeline, we cannot do the same
to the clauses in a SQL query.  This is because the SQL grammar arranges the
clauses in a rigid order:

1) `FROM`, followed by zero, one or more
2) `JOIN`, followed by
3) `WHERE`, followed by
4) `GROUP BY`, followed by
5) `HAVING`, followed by
6) `ORDER BY`, followed by
7) `LIMIT`, followed by
8) `SELECT`, written at the top of the query, but the last one to perform.

This order allows us to convert our first pipeline, with the `Where` node
followed by `Order` and `Limit`, but not the second pipeline, where these nodes
change their relative positions.  So how could the second pipeline be converted
to SQL?  We would be out of options if we were still using the original SQL
standard, SQL-86, but the next revision of the language, SQL-92, recognized
this limitation.  Regrettably, instead of relaxing this rigid clause order,
SQL-92 introduced a workaround: two queries are composed by nesting the first
query into the second query's `FROM` clause.  This gives us a method for
converting an arbitrary pipeline into SQL: break the pipeline into smaller
chunks that comply with the SQL clause order, convert each chunk into a SQL
query, and then nest all these queries together:
```sql
SELECT "person_2"."person_id"
FROM (
  SELECT
    "person_1"."person_id",
    "person_1"."gender_concept_id"
  FROM "person" AS "person_1"
  ORDER BY "person_1"."year_of_birth"
  LIMIT 100
) AS "person_2"
WHERE ("person_2"."gender_concept_id" = 8507)
```

In practice, this query nesting is a major flaw of the SQL grammar.  This is
because query nesting, in combination with the nonsensical placement of the
`SELECT` clause, violates the logical flow of the query.  Complex SQL queries
often require multiple levels of nesting, which makes such queries complicated,
ugly, and difficult to understand.

But we diverged from our main topic.  What about the other kind of query
builders?  Active Record and Laravel employ a pipeline of exactly the same
form, but because it is not sensitive to the order of the nodes, it must work
on a different principle.  Indeed, this pipeline generates a SQL query by
incrementally assembling the SQL syntax tree.  Because of the rigid clause
order, a SQL syntax tree can be faithfully represented as a composite data
structure with slots specifying the content of the `SELECT`, `FROM`, `WHERE`,
and the other clauses:
```julia
struct SQLQuery
    select_clause
    from_clause
    join_clauses
    where_clause
    groupby_clause
    having_clause
    orderby_clause
    limit_clause
end
```
Individual slots of this structure are populated by the corresponding pipeline
nodes.

*Diagram*

This explains why the pipeline is insensitive to the order of the nodes.
Indeed, as long as the content of the slots stays the same, it makes no
difference in what order the slots are populated.

*Diagram*

This method of incrementally constructing a composite structure is known as the
[*builder pattern*](https://en.wikipedia.org/wiki/Builder_pattern).  We can
call the query builders that employ this pattern *syntax-oriented*.

Both data-oriented and syntax-oriented query builders are compositional: the
difference is in the nature of the information processed by the units of
composition.  Data-oriented query builders incrementally refine the query
output; syntax-oriented query builders incrementally assemble the SQL syntax
tree.  Their interfaces look almost identical, but their methods of operation
are fundamentally different.

But which one is better?  Syntax-oriented query builders have two definite
advantages: they are easy to implement and they could support the full range of
SQL features.  Indeed, the interface of a syntax-oriented query builder is just
a collection of builders for the SQL syntax tree.  How complete the
representation of the syntax tree determines how well various SQL features are
supported.

On the other hand, syntax-oriented query builders are harder to *use*.  As they
directly represent the SQL grammar, they inherit all of its flaws.  In
particular, the rigid clause order makes it difficult to assemble complex data
processing pipelines, especially when the form of the pipeline is not
predetermined.

A data-oriented query builder directly represents data processing nodes, which
makes assembling data processing pipelines much more straightforward—as long as
we can find the necessary nodes among those offered by the builder.  But where
does the builder get its collection of data processing nodes?  And how can we
tell if this collection is complete?

Among data-oriented SQL query builders, EF/LINQ and dbplyr are originated from
general-purpose query frameworks: EF/LINQ from
[LINQ](https://docs.microsoft.com/en-us/dotnet/standard/using-linq) and dbplyr
from [dplyr](https://dplyr.tidyverse.org/).  These query frameworks determine
what processing nodes are available and how they operate.  The question is: how
a query framework is made compatible with SQL databases?  In principle, this
can be done by extending the framework with just one node, a node that loads
the content of a database table.  This node is placed at the beginning of a
pipeline, while regular nodes make the rest of the pipeline.  This pipeline can
run directly, although it is very inefficient compared to using the SQL engine.
The SQL engine can use indexes and other optimization techniques to avoid
loading the whole table into memory and thus can process the same data much
faster.  This is why EF/LINQ and dbplyr generate a SQL query to replace the
entire pipeline.  The pipeline itself no longer runs directly, but now serves
as a specification, describing the output that we expect the SQL query to
produce.  This method of adapting a general-purpose query framework to a SQL
database is called *SQL pushdown*.

However, SQL pushdown has serious limitations.  A general-purpose query
framework is not designed with SQL compatibility in mind.  For this reason,
some pipelines assembled with this framework cannot be translated to SQL.  Even
worse, many valid SQL queries have no equivalent pipelines and thus cannot be
assembled using SQL pushdown.  SQL accumulated a wide range of features and
capabilities since it first appeared in 1974.  The first version of the SQL
standard, SQL-86, supported Cartesian products, filtering, grouping,
aggregation, and correlated subqueries.  The next version, SQL-92, added many
join types and introduced query nesting.  SQL:1999 added two new types of
queries: recursive queries, to enable bill-of-material calculations, and data
cube queries, which generalize histograms, cross-tabulations, roll-ups,
drill-downs, and sub-totals.  Further, SQL:2003 added support for aggregation
over a running window.  SQL is a quintessential *enterprise abomination*, a
hodgepodge of features added to support every imaginable use case, but with
weird gaps, inadequate syntax, and no regards to internal consistency.
Nevertheless, the breadth of SQL capabilities has not been matched by any other
query framework, including LINQ or dplyr.  So when we generate SQL queries
using EF/LINQ or dbplyr, a large subset of these capabilities remains
inaccessible.

FunSQL is a data-oriented query builder that was specifically created to expose
full expressive power of SQL.  Unlike EF/LINQ and dbplyr, FunSQL is not derived
from an independent query framework, and FunSQL pipelines cannot be run
directly.  However, every FunSQL node has a well-defined data processing
semantics, and, in principle, a query framework based on FunSQL can be
implemented.  At the same time, FunSQL nodes are carefully designed to match
SQL capabilities, including, for example, correlated subqueries and lateral
joins, aggregate and window functions, as well as recursive queries.  This
makes FunSQL the first and the only query builder suitable for assembling
complex data processing pipelines for SQL databases.
