#!/usr/bin/env julia

using FunSQL:
    SQLTable, UnitClause, FromClause, SelectClause, WhereClause, HavingClause,
    GroupClause, WindowClause, JoinClause, UnionClause, From, Select, Where,
    Bind, Join, Group, Window, Append, Fun, Get, Agg, Literal, As, to_sql,
    normalize

patient = SQLTable(:public, :patient, [:id, :mrn, :sex, :father_id, :mother_id])
encounter = SQLTable(:public, :encounter, [:id, :patient_id, :code, :date])
condition = SQLTable(:public, :condition, [:id, :patient_id, :code, :date])

# Constructing SQL syntax.

q = Literal(:patient) |>
    FromClause() |>
    SelectClause(Literal(:mrn))
println(to_sql(q))

q = Literal(:patient) |>
    FromClause() |>
    SelectClause(Literal(:sex), distinct=true)
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    WhereClause(Fun."="(Literal((:p, :sex)), "male")) |>
    SelectClause(Literal((:p, :mrn)))
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    JoinClause(Literal(:encounter) |> As(:e),
               Fun."="(Literal((:p, :id)), Literal((:e, :patient_id)))) |>
    SelectClause(Literal((:p, :mrn)), Literal((:e, :date)))
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    WhereClause(Fun."="(Literal((:p, :sex)), "male")) |>
    SelectClause(Literal((:p, :id)), Literal((:p, :mrn))) |>
    As(:p) |>
    FromClause() |>
    JoinClause(Literal(:encounter) |> As(:e),
               Fun."="(Literal((:p, :id)), Literal((:e, :patient_id)))) |>
    SelectClause(Literal((:p, :mrn)), Literal((:e, :date)))
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    GroupClause(Literal((:p, :sex))) |>
    SelectClause(Literal((:p, :sex)), Agg.Count())
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    GroupClause(Literal((:p, :sex))) |>
    HavingClause(Fun.">"(Agg.Count(), 2)) |>
    SelectClause(Literal((:p, :sex)), Agg.Count())
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    JoinClause(Literal(:encounter) |>
               As(:e) |>
               FromClause() |>
               GroupClause(Literal((:e, :patient_id))) |>
               SelectClause(Literal((:e, :patient_id)),
                            Agg.Count() |> As(:count)) |>
               As(:e_grp),
               Fun."="(Literal((:p, :id)), Literal((:e_grp, :patient_id))),
               is_left=true) |>
    SelectClause(Literal((:p, :mrn)),
                 Fun.Coalesce(Literal((:e_grp, :count)), 0))
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    WhereClause(Fun."="(Literal((:p, :id)), 1)) |>
    SelectClause(Literal((:p, :mrn))) |>
    UnionClause(
        Literal(:patient) |>
        As(:c) |>
        FromClause() |>
        WhereClause(Fun."OR"(Fun."="(Literal((:c, :father_id)), 1),
                             Fun."="(Literal((:c, :mother_id)), 1))) |>
        SelectClause(Literal((:c, :mrn)))) |>
    As(:n) |>
    FromClause() |>
    SelectClause(Literal((:n, :mrn)))
println(to_sql(q))

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    WindowClause(Literal((:p, :sex))) |>
    As(:w) |>
    SelectClause(Literal((:p, :mrn)),
                 Agg.Count(over=Literal(:w)),
                 Agg.Row_Number(over=Literal(:w)))
println(to_sql(q))

#=
    SELECT EXISTS(SELECT TRUE FROM patient)
=#

q = UnitClause() |>
    SelectClause(Fun.Exists(Literal(:patient) |>
                            FromClause() |>
                            SelectClause(true)))
println(to_sql(q))

#=
    SELECT p.mrn
    FROM patient p
    WHERE EXISTS(
        SELECT TRUE
        FROM patient c
        WHERE c.father_id = p.id OR c.mother_id = p.id)
=#

q = Literal(:patient) |>
    As(:p) |>
    FromClause() |>
    WhereClause(
        Fun.Exists(
            Literal(:patient) |>
            As(:c) |>
            FromClause() |>
            WhereClause(
                Fun.Or(Fun."="(Literal((:c, :father_id)), Literal((:p, :id))),
                       Fun."="(Literal((:c, :mother_id)), Literal((:p, :id))))) |>
            SelectClause(true))) |>
    SelectClause(Literal((:p, :mrn)))
println(to_sql(q))


# Semantic operators.

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
    Join(:encounter => encounter |> Group(Get.patient_id),
         Fun."="(Get.id, Get.encounter.patient_id),
         is_left=true) |>
    Select(
        Get.mrn,
        "date of the first encounter" => Agg.Min(Get.date, over=Get.encounter),
        "# encounters" => Agg.Count())
println(to_sql(normalize(q)))

q = patient |>
    Join(:encounter => encounter |> Group(Get.patient_id),
         Fun."="(Get.id, Get.encounter.patient_id),
         is_left=true) |>
    Join(:condition => condition |> Group(Get.patient_id),
         Fun."="(Get.id, Get.condition.patient_id),
         is_left=true) |>
    Where(Fun."="(Get.sex, "male")) |>
    Select(
        Get.mrn,
        "date of the first encounter" => Agg.Min(Get.date, over=Get.encounter),
        "# encounters" => Agg.Count(over=Get.encounter),
        "# conditions" => Agg.Count(over=Get.condition))
println(to_sql(normalize(q)))

q = patient |>
    Window(Get.sex, order=[Get.mrn]) |>
    Select(Get.mrn, Agg.Count(), Agg.Row_Number())
println(to_sql(normalize(q)))


#=
    SELECT EXISTS(SELECT TRUE FROM patient)
=#

q = From(nothing)
println(to_sql(normalize(q)))

q = From(nothing) |>
    Select(Fun.Exists(From(patient)))
println(to_sql(normalize(q)))

#=
    SELECT p.mrn
    FROM patient p
    WHERE EXISTS(
        SELECT TRUE
        FROM patient c
        WHERE c.father_id = p.id OR c.mother_id = p.id)
=#

subq(parent_id) =
    From(patient) |>
    Where(Fun.Or(Fun."="(Get.father_id, Get.parent_id),
                 Fun."="(Get.mother_id, Get.parent_id))) |>
    Bind(:parent_id => parent_id)

q = subq(1)
println(to_sql(normalize(q)))

q = subq(1) |> Select(Get.mrn)
println(to_sql(normalize(q)))

q = patient |>
    Where(Fun.Exists(subq(Get.id)))
println(to_sql(normalize(q)))

#=
    SELECT p.mrn, c.mrn
    FROM patient p
    LEFT JOIN LATERAL (
        SELECT c.mrn
        FROM patient c
        WHERE c.father_id = p.id OR c.mother_id = p.id
        LIMIT 1
    ) ON (TRUE) AS c
=#

q = patient |>
    Join(:child => subq(Get.id), true) |>
    Select(Get.mrn, Get.child.mrn)
println(to_sql(normalize(q)))

