# Schema reflection.

const default_reflect_clause =
    FROM(:c => (:information_schema, :columns)) |>
    WHERE(FUN("=", (:c, :table_schema), VAR(:schema))) |>
    ORDER((:c, :table_schema), (:c, :table_name), (:c, :ordinal_position)) |>
    SELECT(:schema => (:c, :table_schema),
           :name => (:c, :table_name),
           :column => (:c, :column_name))
const duckdb_reflect_clause =
    FROM(:c => (:information_schema, :columns)) |>
    WHERE(FUN(:and, FUN("=", (:c, :table_schema), FUN(:coalesce, VAR(:schema), "main")),
                    FUN(:not_like, (:c, :table_name), "sqlite_%"),
                    FUN(:not_like, (:c, :table_name), "pragma_database_list"))) |>
    ORDER((:c, :table_schema), (:c, :table_name), (:c, :ordinal_position)) |>
    SELECT(:schema => (:c, :table_schema),
           :name => (:c, :table_name),
           :column => (:c, :column_name))
const mysql_reflect_clause =
    FROM(:c => (:information_schema, :columns)) |>
    WHERE(FUN("=", (:c, :table_schema), FUN(:coalesce, VAR(:schema), FUN("DATABASE")))) |>
    ORDER((:c, :table_schema), (:c, :table_name), (:c, :ordinal_position)) |>
    SELECT(:schema => (:c, :table_schema),
           :name => (:c, :table_name),
           :column => (:c, :column_name))
const postgresql_reflect_clause =
    FROM(:n => (:pg_catalog, :pg_namespace)) |>
    JOIN(:c => (:pg_catalog, :pg_class), on = FUN("=", (:n, :oid), (:c, :relnamespace))) |>
    JOIN(:a => (:pg_catalog, :pg_attribute), on = FUN("=", (:c, :oid), (:a, :attrelid))) |>
    WHERE(FUN(:and, FUN("=", (:n, :nspname), FUN(:coalesce, VAR(:schema), "public")),
                    FUN(:in, (:c, :relkind), "r", "v"),
                    FUN(">", (:a, :attnum), 0),
                    FUN(:not, (:a, :attisdropped)))) |>
    ORDER((:n, :nspname), (:c, :relname), (:a, :attnum)) |>
    SELECT(:schema => (:n, :nspname),
           :name => (:c, :relname),
           :column => (:a, :attname))
const redshift_reflect_clause = postgresql_reflect_clause
const sqlite_reflect_clause =
    FROM(:sm => :sqlite_master) |>
    JOIN(:pti => FUN(:pragma_table_info, (:sm, :name)), on = true) |>
    WHERE(FUN(:and, FUN(:in, (:sm, :type), "table", "view"),
                    FUN(:not_like, (:sm, :name), "sqlite_%"))) |>
    ORDER((:sm, :name), (:pti, :cid)) |>
    SELECT(:schema => missing,
           :name => (:sm, :name),
           :column => (:pti, :name))
const sqlserver_reflect_clause =
    FROM(:s => (:sys, :schemas)) |>
    JOIN(:o => (:sys, :objects), on = FUN("=", (:s, :schema_id), (:o, :schema_id))) |>
    JOIN(:c => (:sys, :columns), on = FUN("=", (:o, :object_id), (:c, :object_id))) |>
    WHERE(FUN(:and, FUN("=", (:s, :name), FUN(:coalesce, VAR(:schema), "dbo")),
                    FUN(:in, (:o, :type), "U", "V"))) |>
    ORDER((:s, :name), (:o, :name), (:c, :column_id)) |>
    SELECT(:schema => (:s, :name),
           :name => (:o, :name),
           :column => (:c, :name))
const standard_reflect_clauses = [
    :duckdb => duckdb_reflect_clause,
    :mysql => mysql_reflect_clause,
    :postgresql => postgresql_reflect_clause,
    :redshift => redshift_reflect_clause,
    :sqlite => sqlite_reflect_clause,
    :sqlserver => sqlserver_reflect_clause]

function reflect_clause(d::SQLDialect)
    for (name, clause) in standard_reflect_clauses
        if name === d.name
            return clause
        end
    end
    return default_reflect_clause
end

reflect_sql(d::SQLDialect) =
    render(reflect_clause(d), dialect = d)

"""
    reflect(conn;
            schema = nothing,
            dialect = nothing,
            cache = $default_cache_maxsize)::SQLCatalog

Retrieve the information about available database tables.

The function returns a [`SQLCatalog`](@ref) object.  The catalog
will be populated with the tables from the given database `schema`, or,
if parameter `schema` is not set, from the default database schema
(e.g., schema `public` for PostgreSQL).

Parameter `dialect` specifies the target [`SQLDialect`](@ref).  If not set,
`dialect` will be inferred from the type of the connection object.

"""
function reflect(conn; schema = nothing, dialect = nothing, cache = default_cache_maxsize)
    dialect = dialect === nothing ? SQLDialect(typeof(conn)) : convert(SQLDialect, dialect)
    sql = reflect_sql(dialect)
    params = pack(sql, (; schema = something(schema, missing)))
    stmt = DBInterface.prepare(conn, String(sql))
    cr = DBInterface.execute(stmt, params)
    SQLCatalog(tables = tables_from_column_list(Tables.rows(cr)),
               dialect = dialect,
               cache = cache)
end

function tables_from_column_list(rows)
    tables = SQLTable[]
    qualifiers = Symbol[]
    schema = name = nothing
    columns = Symbol[]
    for (s, n, c) in rows
        s = s !== missing ? Symbol(s) : nothing
        n = Symbol(n)
        c = Symbol(c)
        if s === schema && n === name
            push!(columns, c)
        else
            if !isempty(columns)
                t = SQLTable(qualifiers = qualifiers, name = name, columns = columns)
                push!(tables, t)
            end
            if s !== schema
                qualifiers = s !== nothing ? [s] : Symbol[]
            end
            schema = s
            name = n
            columns = [c]
        end
    end
    if !isempty(columns)
        t = SQLTable(qualifiers = qualifiers, name = name, columns = columns)
        push!(tables, t)
    end
    tables
end
