using FunSQL: SQLTable, Agg, From, Get, Group, Join, Select, Where, normalize, to_sql
using DataKnots: DataKnot
using LibPQ

conn = LibPQ.Connection("")

const person =
    SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id])

const location =
    SQLTable(:location, columns = [:location_id, :city, :state, :zip])

const visit_occurrence =
    SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date])

#=
When was the last time each person born in 2000 or earlier and living in
Illinois was seen by a care provider?
=#

q = From(person) |>
    Where(Get.year_of_birth .<= 2000) |>
    Join(:location => From(location),
         on = (Get.location_id .== Get.location.location_id)) |>
    Where(Get.location.state .== "IL") |>
    Join(:visit_group => From(visit_occurrence) |>
                         Group(Get.person_id),
         on = (Get.person_id .== Get.visit_group.person_id),
         left = true) |>
    Select(Get.person_id,
           :max_visit_start_date =>
               Get.visit_group |> Agg.Max(Get.visit_start_date))

sql = to_sql(normalize(q))

result = execute(conn, sql)
println(convert(DataKnot, result))

sql = """
SELECT p.person_id, MAX(vo.visit_start_date)
FROM person p
JOIN location l ON (p.location_id = l.location_id)
LEFT JOIN visit_occurrence vo ON (p.person_id = vo.person_id)
WHERE (p.year_of_birth <= 2000) AND (l.state = 'IL')
GROUP BY p.person_id
"""

result = execute(conn, sql)
println(convert(DataKnot, result))
