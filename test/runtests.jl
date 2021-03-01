#!/usr/bin/env julia

using FunSQL: SQLTable, From, Select, Where, Join, Group, Fun, Get, Agg, to_sql, normalize

patient = SQLTable(:public, :patient, [:id, :mrn, :sex])
encounter = SQLTable(:public, :encounter, [:id, :patient_id, :code, :date])
condition = SQLTable(:public, :condition, [:id, :patient_id, :code, :date])

q = From(patient)
println(to_sql(normalize(q)))

q = q |> Select(q[:mrn], q[:sex])
println(to_sql(normalize(q)))

q = From(patient) |>
    Select(Get.mrn, Get.sex, Fun."="(Get.sex, "male"))
println(to_sql(normalize(q)))

q = patient |>
    Where(Fun."="(Get.sex, "male")) |>
    Select(Get.mrn)
println(to_sql(normalize(q)))

q = patient |>
    Join(:encounter => encounter,
         Fun."="(Get.id, Get.encounter.patient_id),
         is_left=true) |>
    Select(Get.mrn, Get.encounter.date)
println(to_sql(normalize(q)))

q = patient |>
    Group(Get.sex) |>
    Select(Get.sex, Agg.Count())
println(to_sql(normalize(q)))

q = patient |>
    Join(:encounter => (encounter |> Group(Get.patient_id)),
         Fun."="(Get.id, Get.encounter.patient_id),
         is_left=true) |>
    Select(
        Get.mrn,
        "date of the first encounter" => Agg.Min(Get.encounter.date, over=Get.encounter),
        "# encounters" => Agg.Count())
println(to_sql(normalize(q)))

q = patient |>
    Join(:encounter => (encounter |> Group(Get.patient_id)),
         Fun."="(Get.id, Get.encounter.patient_id),
         is_left=true) |>
    Join(:condition => (condition |> Group(Get.patient_id)),
         Fun."="(Get.id, Get.condition.patient_id),
         is_left=true) |>
    Where(Fun."="(Get.sex, "male")) |>
    Select(
        Get.mrn,
        "date of the first encounter" => Agg.Min(Get.encounter.date, over=Get.encounter),
        "# encounters" => Agg.Count(over=Get.encounter),
        "# conditions" => Agg.Count(over=Get.condition))
println(to_sql(normalize(q)))

