### A Pluto.jl notebook ###
# v0.14.2

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    quote
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : missing
        el
    end
end

# ╔═╡ 8bd5e01c-418b-4dd8-ba9f-cb4f932bef03
begin
	using FunSQL:
		SQLTable, Agg, From, Fun, Get, Group, Join, Select, Where, render	

	using PlutoUI
	using LibPQ
	using Tables
	using Plots
end

# ╔═╡ 32077f7b-90df-445b-b347-8bc9f921ab00
md"""
# Exploring OHDSI Database
"""

# ╔═╡ 4823e73d-1c92-4496-a19e-934891e0568c
begin
	DEFAULT_PGHOST = get(ENV, "PGHOST", "/var/run/postgresql")
	DEFAULT_PGPORT = parse(Int, get(ENV, "PGPORT", "5432"))
	DEFAULT_PGUSER = get(ENV, "PGUSER", "")
	DEFAULT_PGPASSWORD = get(ENV, "PGPASSWORD", "")

	md"""
	## Configure Database Connection
	
	**Host:**
	$(@bind PGHOST TextField(default = DEFAULT_PGHOST))

	**Port:**
	$(@bind PGPORT NumberField(1:65535, default = DEFAULT_PGPORT))

	**Username:**
	$(@bind PGUSER TextField(default = DEFAULT_PGUSER))

	**Password:**
	$(@bind PGPASSWORD PasswordField(default = DEFAULT_PGPASSWORD))
	"""
end

# ╔═╡ 70b51b71-2da1-49cf-b798-1998592218bc
md"""
## Statistics
"""

# ╔═╡ 0fd29899-809c-4c02-88db-927af32dc6d2
md"""
## Appendix
"""

# ╔═╡ 90701e34-1a2b-4b44-b4dd-33b3de26559e
function escape_connection_parameter(p)
	(key, val) = p
	val = replace(val, '\\' => "\\\\")
	val = replace(val, '\'' => "\\'")
	"$key='$val'"
end

# ╔═╡ 68425c70-5370-4339-900d-83cc9fd9361b
function connect(db)
	db != "" || return nothing
	params = Pair{String, String}[]
	if PGHOST != ""
		push!(params, "host" => PGHOST)
	end
	push!(params, "port" => string(PGPORT))
	if PGUSER != ""
		push!(params, "user" => PGUSER)
	end
	if PGPASSWORD != ""
		push!(params, "password" => PGPASSWORD)
	end
	push!(params, "dbname" => db)
	url = join([escape_connection_parameter(p) for p in params], " ")
	try
		LibPQ.Connection(url)
	catch exc
		exc isa LibPQ.Errors.LibPQException || rethrow()
		nothing
	end
end

# ╔═╡ 2c2e8c34-aed1-4620-959f-b28a89c693d3
begin
	function run(f, c, q; default = nothing)
		c !== nothing || return default
		r = LibPQ.execute(c, render(q))
		f(r)
	end
	
	run(c, q; default = nothing) = run(identity, c, q; default = default)
end

# ╔═╡ 958a0422-06da-4510-a830-21ed6b871cf1
maintenance_connection = connect("postgres")

# ╔═╡ 004cb1fa-6763-4da6-94a7-ecbd9b6e5345
begin
	pg_database =
		SQLTable(schema = :pg_catalog, :pg_database, :oid, :datname, :datistemplate)
	pg_namespace =
		SQLTable(schema = :pg_catalog, :pg_namespace, :oid, :nspname)
	pg_class =
		SQLTable(schema = :pg_catalog, :pg_class, :oid, :relname, :relnamespace, :relkind)
end;

# ╔═╡ aa12fff2-3a62-469f-ab98-d635758bfdf8
begin
	AvailableDatabases =
		From(pg_database) |>
		Where(
			Fun.and(
				Fun.not(Get.datistemplate),
				Fun.has_database_privilege(Get.oid, "CONNECT")))

	available_databases =
		run(maintenance_connection, AvailableDatabases, default = []) do rows
			[row.datname for row in rows]
		end
end

# ╔═╡ 9207c58a-1042-4ab9-867e-b1b9e4e8fb99
begin
	HasTable(name) =
		Agg.count(filter = Get.relname .== name) .> 0
	
	HasTables(names...) =
		Fun.and(HasTable.(names)...)
	
	IsEligible =
		From(pg_class) |>
		Where(Get.relkind .== "r") |>
		Join(:nsp => pg_namespace, Get.relnamespace .== Get.nsp.oid) |>
		Where(Get.nsp.nspname .== "public") |>
		Group() |>
		Select(HasTables("concept", "person", "location"))

	function is_eligible(db)
		c = connect(db)
		run(c, IsEligible, default = false) do rows
			rows[1,1]
		end
	end
	
	eligible_databases = filter(is_eligible, available_databases)
end

# ╔═╡ 827757af-f2c1-4ca4-a4b6-cdb3b50b6bcb
begin
	PGDATABASE = ""

	if !isempty(eligible_databases)
		md"""
		**Database:**
		$(@bind PGDATABASE PlutoUI.Select(eligible_databases, default = ""))
		"""
	elseif maintenance_connection === nothing
		md"""
		!!! danger "Cannot connect to the database server!"
		"""
	else
		md"""
		!!! danger "Cannot find any OSDSI databases!"
		"""
	end
end

# ╔═╡ 7f3b0bff-e274-4609-8fee-d519e546420b
connection = connect(PGDATABASE)

# ╔═╡ babeb64c-8d49-4c93-a5bc-1e196681e4cb
begin
	concept =
		SQLTable(:concept, :concept_id, :concept_name, :domain_id, :vocabulary_id, :concept_class_id, :standard_concept, :concept_code, :valid_start_date, :valid_end_date, :invalid_reason)
	person =
		SQLTable(:person, :person_id, :gender_concept_id, :year_of_birth, :month_of_birth, :day_of_birth, :time_of_birth, :race_concept_id, :ethnicity_concept_id, :location_id, :provider_id, :care_site_id)
	location =
		SQLTable(:location, :location_id, :address_1, :address_2, :city, :state, :zip,  :county)
end;

# ╔═╡ 946e95bc-b330-42d4-906c-dd55bbdc49d6
begin
	PersonTotal = From(person) |> Group() |> Select(Agg.count())

	run(connection, PersonTotal) do rows
		data = ("Total", rows[1, 1])
		bar(data, title = "Total # of patients", legend = false, formatter = :plain)
	end
end

# ╔═╡ 9f4f069f-0cfe-4837-99a7-be094427e45d
begin
	PersonBySex =
		From(person) |>
		Group(Get.gender_concept_id) |>
		Join(concept, Get.gender_concept_id .== Get.concept_id) |>
		Select(Get.concept_code, Agg.count())
	
	run(connection, PersonBySex) do rows
		data = [(row[1], row[2]) for row in rows]
		bar(data, title = "Patients by Sex",  legend = false, formatter = :plain)
	end
end

# ╔═╡ 8a22dd67-610a-449c-a17d-004c8c7cfd61
begin
	PersonByYOB =
		From(person) |>
		Group(Get.year_of_birth) |>
		Select(Get.year_of_birth, Agg.count())
	
	run(connection, PersonByYOB) do rows
		data = [(row[1], row[2]) for row in rows]
		bar(data, title = "Patients By Year of Birth", legend = false, formatter = :plain)
	end
end

# ╔═╡ Cell order:
# ╟─32077f7b-90df-445b-b347-8bc9f921ab00
# ╟─4823e73d-1c92-4496-a19e-934891e0568c
# ╟─827757af-f2c1-4ca4-a4b6-cdb3b50b6bcb
# ╟─70b51b71-2da1-49cf-b798-1998592218bc
# ╠═946e95bc-b330-42d4-906c-dd55bbdc49d6
# ╠═9f4f069f-0cfe-4837-99a7-be094427e45d
# ╠═8a22dd67-610a-449c-a17d-004c8c7cfd61
# ╟─0fd29899-809c-4c02-88db-927af32dc6d2
# ╠═8bd5e01c-418b-4dd8-ba9f-cb4f932bef03
# ╠═90701e34-1a2b-4b44-b4dd-33b3de26559e
# ╠═68425c70-5370-4339-900d-83cc9fd9361b
# ╠═2c2e8c34-aed1-4620-959f-b28a89c693d3
# ╠═958a0422-06da-4510-a830-21ed6b871cf1
# ╠═004cb1fa-6763-4da6-94a7-ecbd9b6e5345
# ╠═aa12fff2-3a62-469f-ab98-d635758bfdf8
# ╠═9207c58a-1042-4ab9-867e-b1b9e4e8fb99
# ╠═7f3b0bff-e274-4609-8fee-d519e546420b
# ╠═babeb64c-8d49-4c93-a5bc-1e196681e4cb
