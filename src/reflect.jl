# Schema reflection.

const default_reflect_clause =
    FROM(:c => (:information_schema, :columns)) |>
    WHERE(OP("=", (:c, :table_schema), VAR(:schema))) |>
    ORDER((:c, :table_schema), (:c, :table_name), (:c, :ordinal_position)) |>
    SELECT(:schema => (:c, :table_schema),
           :name => (:c, :table_name),
           :column => (:c, :column_name))
const mysql_reflect_clause =
    FROM(:c => (:information_schema, :columns)) |>
    WHERE(OP("=", (:c, :table_schema), FUN(:COALESCE, VAR(:schema), FUN(:DATABASE)))) |>
    ORDER((:c, :table_schema), (:c, :table_name), (:c, :ordinal_position)) |>
    SELECT(:schema => (:c, :table_schema),
           :name => (:c, :table_name),
           :column => (:c, :column_name))
const postgresql_reflect_clause =
    FROM(:n => (:pg_catalog, :pg_namespace)) |>
    JOIN(:c => (:pg_catalog, :pg_class), on = OP("=", (:n, :oid), (:c, :relnamespace))) |>
    JOIN(:a => (:pg_catalog, :pg_attribute), on = OP("=", (:c, :oid), (:a, :attrelid))) |>
    WHERE(OP(:AND, OP("=", (:n, :nspname), FUN(:COALESCE, VAR(:schema), "public")),
                   OP(:IN, (:c, :relkind), FUN("", "r", "v")),
                   OP(">", (:a, :attnum), 0),
                   OP(:NOT, (:a, :attisdropped)))) |>
    ORDER((:n, :nspname), (:c, :relname), (:a, :attnum)) |>
    SELECT(:schema => (:n, :nspname),
           :name => (:c, :relname),
           :column => (:a, :attname))
const redshift_reflect_clause = postgresql_reflect_clause
const sqlite_reflect_clause =
    FROM(:sm => :sqlite_master) |>
    JOIN(:pti => FUN(:pragma_table_info, (:sm, :name)), on = true) |>
    WHERE(OP(:AND, OP(:IN, (:sm, :type), FUN("", "table", "view")),
                   OP("NOT LIKE", (:sm, :name), "sqlite_%"))) |>
    ORDER((:sm, :name), (:pti, :cid)) |>
    SELECT(:schema => missing,
           :name => (:sm, :name),
           :column => (:pti, :name))
const sqlserver_reflect_clause =
    FROM(:s => (:sys, :schemas)) |>
    JOIN(:o => (:sys, :objects), on = OP("=", (:s, :schema_id), (:o, :schema_id))) |>
    JOIN(:c => (:sys, :columns), on = OP("=", (:o, :object_id), (:c, :object_id))) |>
    WHERE(OP(:AND, OP("=", (:s, :name), FUN(:COALESCE, VAR(:schema), "dbo")),
                   OP(:IN, (:o, :type), FUN("", "U", "V")))) |>
    ORDER((:s, :name), (:o, :name), (:c, :column_id)) |>
    SELECT(:schema => (:s, :name),
           :name => (:o, :name),
           :column => (:c, :name))
const standard_reflect_clauses = [
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

function reflect(conn; schema = nothing, dialect = SQLDialect(typeof(conn)), cache = default_cache_maxsize)
    dialect = convert(SQLDialect, dialect)
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
                t = SQLTable(schema = schema, name = name, columns = columns)
                push!(tables, t)
            end
            schema = s
            name = n
            columns = [c]
        end
    end
    if !isempty(columns)
        t = SQLTable(schema = schema, name = name, columns = columns)
        push!(tables, t)
    end
    tables
end

