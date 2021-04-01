using FunSQL: SQLTable, Agg, From, Get, Group, Join, Select, Where, normalize, to_sql
using DataKnots: DataKnot
using LibPQ

const person =
    SQLTable(:person, columns = [:person_id, :year_of_birth, :location_id])

const location =
    SQLTable(:location, columns = [:location_id, :city, :state, :zip])

const visit_occurrence =
    SQLTable(:visit_occurrence, columns = [:visit_occurrence_id, :person_id, :visit_start_date])

q = From(person) |>
    Where(2021 .- Get.year_of_birth .>= 18) |>
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
conn = LibPQ.Connection("")
result = execute(conn, sql)
println(convert(DataKnot, result))
