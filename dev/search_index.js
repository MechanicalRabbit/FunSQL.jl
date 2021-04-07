var documenterSearchIndex = {"docs":
[{"location":"#FunSQL.jl","page":"Home","title":"FunSQL.jl","text":"","category":"section"},{"location":"#API-Reference","page":"Home","title":"API Reference","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"FunSQL.render","category":"page"},{"location":"#FunSQL.render","page":"Home","title":"FunSQL.render","text":"render(node; dialect = :default) :: String\n\nConvert the given SQL node or clause object to a SQL string.\n\n\n\n\n\n","category":"function"},{"location":"#SQL-Dialects","page":"Home","title":"SQL Dialects","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Modules = [FunSQL]\nPages = [\"dialects.jl\"]","category":"page"},{"location":"#FunSQL.SQLDialect","page":"Home","title":"FunSQL.SQLDialect","text":"Properties of a SQL dialect.\n\n\n\n\n\n","category":"type"},{"location":"#SQL-Entities","page":"Home","title":"SQL Entities","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Modules = [FunSQL]\nPages = [\"entities.jl\"]","category":"page"},{"location":"#FunSQL.SQLTable","page":"Home","title":"FunSQL.SQLTable","text":"SQLTable(; schema = nothing, name, columns)\nSQLTable(name; schema = nothing, columns)\nSQLTable(name, columns...; schema = nothing)\n\nThe structure of a SQL table or a table-like entity (TEMP TABLE, VIEW, etc) for use as a reference in assembling SQL queries.\n\nThe SQLTable constructor expects the table name, a vector columns of column names, and, optionally, the name of the table schema.  A name can be provided as a Symbol or String value.\n\nExamples\n\njulia> t = SQLTable(:location,\n                    :location_id, :address_1, :address_2, :city, :state, :zip);\n\n\njulia> show(t.name)\n:location\n\njulia> show(t.columns)\n[:location_id, :address_1, :address_2, :city, :state, :zip]\n\njulia> t = SQLTable(schema = \"public\",\n                    name = \"person\",\n                    columns = [\"person_id\", \"birth_datetime\", \"location_id\"]);\n\njulia> show(t.schema)\n:public\n\njulia> show(t.name)\n:person\n\njulia> show(t.columns)\n[:person_id, :birth_datetime, :location_id]\n\n\n\n\n\n","category":"type"},{"location":"#Semantic-Structure","page":"Home","title":"Semantic Structure","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Modules = [FunSQL]\nPages = [\n    \"nodes.jl\",\n    \"nodes/as.jl\",\n    \"nodes/call.jl\",\n    \"nodes/from.jl\",\n    \"nodes/get.jl\",\n    \"nodes/highlight.jl\",\n    \"nodes/literal.jl\",\n    \"nodes/select.jl\",\n    \"nodes/where.jl\",\n]","category":"page"},{"location":"#FunSQL.AbstractSQLNode","page":"Home","title":"FunSQL.AbstractSQLNode","text":"A SQL expression.\n\n\n\n\n\n","category":"type"},{"location":"#FunSQL.SQLNode","page":"Home","title":"FunSQL.SQLNode","text":"An opaque wrapper over an arbitrary SQL node.\n\n\n\n\n\n","category":"type"},{"location":"#FunSQL.As-Tuple","page":"Home","title":"FunSQL.As","text":"As(; over = nothing; name)\nAs(name; over = nothing)\nname => over\n\nAn alias for a subquery or an expression.\n\nExamples\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person) |>\n           As(:p) |>\n           Select(:birth_year => Get.p.year_of_birth);\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.Call-Tuple","page":"Home","title":"FunSQL.Call","text":"Call(; name, args = [])\nCall(name; args = [])\nCall(name, args...)\n\nA function or an operator invocation.\n\nExample\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person) |>\n           Where(Call(\"NOT\", Call(\">\", Get.person_id, 2000)));\n\njulia> print(render(q))\nSELECT \"person_1\".\"person_id\", \"person_1\".\"year_of_birth\"\nFROM \"person\" AS \"person_1\"\nWHERE (NOT (\"person_1\".\"person_id\" > 2000))\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.From-Tuple","page":"Home","title":"FunSQL.From","text":"From(; table)\nFrom(table)\n\nA subquery that selects columns from the given table.\n\nSELECT ... FROM $table\n\nExamples\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person);\n\njulia> print(render(q))\nSELECT \"person_1\".\"person_id\", \"person_1\".\"year_of_birth\"\nFROM \"person\" AS \"person_1\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.Get-Tuple","page":"Home","title":"FunSQL.Get","text":"Get(; over, name)\nGet(name; over)\nGet.name        Get.\"name\"      Get[name]       Get[\"name\"]\nover.name       over.\"name\"     over[name]      over[\"name\"]\n\nA reference to a table column, or an aliased expression or subquery.\n\nExamples\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person) |>\n           As(:p) |>\n           Select(Get.p.person_id);\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person);\n\njulia> q = q |> Select(q.person_id);\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.Highlight-Tuple","page":"Home","title":"FunSQL.Highlight","text":"Highlight(; over = nothing; color)\nHighlight(color; over = nothing)\n\nHighlight over with the given color.\n\nAvailable colors can be found in Base.text_colors.\n\nExamples\n\njulia> q = Get.person_id |> Highlight(:bold);\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.Literal-Tuple","page":"Home","title":"FunSQL.Literal","text":"Literal(; val)\nLiteral(val)\n\nA SQL literal.\n\nIn a suitable context, missing, numbers, strings and datetime values are automatically converted to SQL literals.\n\nExamples\n\njulia> q = Select(:null => missing,\n                  :boolean => true,\n                  :integer => 42,\n                  :text => \"SQL is fun!\",\n                  :date => Date(2000));\n\njulia> print(render(q))\nSELECT NULL AS \"null\", TRUE AS \"boolean\", 42 AS \"integer\", 'SQL is fun!' AS \"text\", '2000-01-01' AS \"date\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.Select-Tuple","page":"Home","title":"FunSQL.Select","text":"Select(; over; list)\nSelect(list...; over)\n\nA subquery that fixes the list of output columns.\n\nSELECT $list... FROM $over\n\nExamples\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person) |>\n           Select(Get.person_id);\n\njulia> print(render(q))\nSELECT \"person_1\".\"person_id\"\nFROM \"person\" AS \"person_1\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.Where-Tuple","page":"Home","title":"FunSQL.Where","text":"Where(; over = nothing, condition)\nWhere(condition; over = nothing)\n\nA subquery that filters by the given condition.\n\nSELECT ... FROM $over WHERE $condition\n\nExamples\n\njulia> person = SQLTable(:person, columns = [:person_id, :year_of_birth]);\n\njulia> q = From(person) |>\n           Where(Call(\">\", Get.year_of_birth, 2000));\n\njulia> print(render(q))\nSELECT \"person_1\".\"person_id\", \"person_1\".\"year_of_birth\"\nFROM \"person\" AS \"person_1\"\nWHERE (\"person_1\".\"year_of_birth\" > 2000)\n\n\n\n\n\n","category":"method"},{"location":"#Syntactic-Structure","page":"Home","title":"Syntactic Structure","text":"","category":"section"},{"location":"","page":"Home","title":"Home","text":"Modules = [FunSQL]\nPages = [\n    \"clauses.jl\",\n    \"clauses/as.jl\",\n    \"clauses/from.jl\",\n    \"clauses/identifier.jl\",\n    \"clauses/literal.jl\",\n    \"clauses/operator.jl\",\n    \"clauses/select.jl\",\n    \"clauses/where.jl\",\n]","category":"page"},{"location":"#FunSQL.AbstractSQLClause","page":"Home","title":"FunSQL.AbstractSQLClause","text":"A part of a SQL query.\n\n\n\n\n\n","category":"type"},{"location":"#FunSQL.SQLClause","page":"Home","title":"FunSQL.SQLClause","text":"An opaque wrapper over an arbitrary SQL clause.\n\n\n\n\n\n","category":"type"},{"location":"#FunSQL.AS-Tuple","page":"Home","title":"FunSQL.AS","text":"AS(; over = nothing, name)\nAS(name; over = nothing)\n\nAn AS clause.\n\nExamples\n\njulia> c = ID(:person) |> AS(:p);\n\njulia> print(render(c))\n\"person\" AS \"p\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.FROM-Tuple","page":"Home","title":"FunSQL.FROM","text":"FROM(; over = nothing)\nFROM(over)\n\nA FROM clause.\n\nExamples\n\njulia> c = ID(:person) |> AS(:p) |> FROM() |> SELECT((:p, :person_id));\n\njulia> print(render(c))\nSELECT \"p\".\"person_id\"\nFROM \"person\" AS \"p\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.ID-Tuple","page":"Home","title":"FunSQL.ID","text":"ID(; over = nothing, name)\nID(name; over = nothing)\n\nA SQL identifier.  Specify over or use the |> operator to make a qualified identifier.\n\nExamples\n\njulia> c = ID(:person);\n\njulia> print(render(c))\n\"person\"\n\njulia> c = ID(:p) |> ID(:birth_datetime);\n\njulia> print(render(c))\n\"p\".\"birth_datetime\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.LIT-Tuple","page":"Home","title":"FunSQL.LIT","text":"LIT(; val)\nLIT(val)\n\nA SQL literal.\n\nIn a context of a SQL clause, missing, numbers, strings and datetime values are automatically converted to SQL literals.\n\nExamples\n\njulia> c = LIT(missing);\n\n\njulia> print(render(c))\nNULL\n\njulia> c = LIT(\"SQL is fun!\");\n\njulia> print(render(c))\n'SQL is fun!'\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.OP-Tuple","page":"Home","title":"FunSQL.OP","text":"OP(; name, args)\nOP(name; args)\nOP(name, args...)\n\nAn application of a SQL operator.\n\nExamples\n\njulia> c = OP(\"NOT\", OP(\"=\", :zip, \"60614\"));\n\njulia> print(render(c))\n(NOT (\"zip\" = '60614'))\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.SELECT-Tuple","page":"Home","title":"FunSQL.SELECT","text":"SELECT(; over = nothing, distinct = false, list)\nSELECT(list...; over = nothing, distinct = false)\n\nA SELECT clause.  Unlike raw SQL, SELECT() should be placed at the end of a clause chain.\n\nSet distinct to true to add a DISTINCT modifier.\n\nExamples\n\njulia> c = SELECT(true, false);\n\njulia> print(render(c))\nSELECT TRUE, FALSE\n\njulia> c = FROM(:location) |>\n           SELECT(distinct = true, :zip);\n\njulia> print(render(c))\nSELECT DISTINCT \"zip\"\nFROM \"location\"\n\n\n\n\n\n","category":"method"},{"location":"#FunSQL.WHERE-Tuple","page":"Home","title":"FunSQL.WHERE","text":"WHERE(; over = nothing, condition)\nWHERE(condition; over = nothing)\n\nA WHERE clause.\n\nExamples\n\njulia> c = FROM(:location) |>\n           WHERE(OP(\"=\", :zip, \"60614\")) |>\n           SELECT(:location_id);\n\njulia> print(render(c))\nSELECT \"location_id\"\nFROM \"location\"\nWHERE (\"zip\" = '60614')\n\n\n\n\n\n","category":"method"}]
}
