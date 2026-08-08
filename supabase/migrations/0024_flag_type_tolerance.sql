-- ============================================================================
--  0024 — تحمّل أنواع الأعلام على الخادم + أداة رصد
--  ⚠ مُطبَّقة على الإنتاج: 2026-07-31 (version 20260731005006)
-- ============================================================================
--
--  الإصلاح الجذري في العميل (م76 — `record_saver.dart:154`). وهذا **دفاع في
--  العمق**: أي جيل عميل آخر (نسخة Vue القديمة إن بقيت تعمل في مكان ما) قد
--  يكتب `isDebt` منطقياً، و`(payload->>'isDebt')::int` يرمي حينها
--  `22P02: invalid input syntax for type integer: "true"` — **وصفٌّ واحد
--  فاسد يُسقط التقرير الشهري كلّه لا سطراً منه**.
--
--  التحمّل هنا يجعل التقرير ينجو. وهو **لا يُغني** عن إصلاح المصدر: قراءة
--  متسامحة تُبقي البيانات مختلطة الأنواع تتراكم بصمت. الاثنان معاً: العميل
--  يكتب نوعاً واحداً، والخادم لا ينكسر إن أخطأ أحد.

create or replace function public.flag_int(v jsonb)
returns int
language sql
immutable
parallel safe
set search_path to 'public', 'extensions', 'pg_temp'
as $$
  select case jsonb_typeof(v)
           when 'boolean' then case when v = 'true'::jsonb then 1 else 0 end
           when 'number'  then (v::text)::numeric::int
           when 'string'  then coalesce(nullif(regexp_replace(v #>> '{}', '[^0-9-]', '', 'g'), '')::int, 0)
           else 0   -- null / object / array / غائب  ⇒ صفر (سلوك coalesce القديم)
         end
$$;

comment on function public.flag_int(jsonb) is
  'م77 — يقرأ عَلَماً منطقياً/رقمياً/نصّياً كعدد 0/1 بلا رمي. يستبدل (payload->>k)::int الهشّ.';

-- ── get_monthly_summary: نفس المنطق حرفياً، مع flag_int بدل ::int العاري ──
create or replace function public.get_monthly_summary(p_month text, p_doctor_pct integer default 50)
returns table(count_recs bigint, cash numeric, total numeric, xfer numeric, doctor numeric, clinic numeric)
language sql
stable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
  with rec as (
    select (r.payload->>'amount')::numeric as amount,
           r.payload->>'payment' as payment,
           flag_int(r.payload->'isDebt') as isDebt,
           flag_int(r.payload->'isPros') as isPros,
           flag_int(r.payload->'isDebtPayment') as isDebtPayment,
           r.payload->>'debtId' as debtId,
           case when d.payload->>'type' = 'prosthetic' then 1 else 0 end as isProsDebtPay
    from sync_rows r
    left join sync_rows d
      on d.user_id = r.user_id and d.entity = 'debts'
     and d.id = r.payload->>'debtId' and d._deleted = false
    where r.user_id = auth.uid() and r.entity = 'records' and r._deleted = false
      and (r.payload->>'date') like p_month || '%'),
  inc as (
    select * from rec where isProsDebtPay = 0 and
      ((isDebt = 0 and isPros = 0 and isDebtPayment = 0 and coalesce(payment, '') <> 'دين')
       or isDebtPayment = 1)),
  agg as (
    select sum(case when isDebtPayment = 0 then 1 else 0 end)::bigint as count_recs,
           round(coalesce(sum(case when payment in ('كاش','نقد','نقدي') then amount else 0 end), 0), 2) as cash,
           round(coalesce(sum(amount), 0), 2) as total
    from inc)
  select count_recs,
         cash,
         total,
         round(total - cash, 2) as xfer,
         round(total * p_doctor_pct / 100.0) as doctor,
         round(total - round(total * p_doctor_pct / 100.0), 2) as clinic
  from agg
$function$;

revoke all on function public.flag_int(jsonb) from public, anon;
grant execute on function public.flag_int(jsonb) to authenticated, service_role;

-- تحقّق (نُفِّذ على الإنتاج، كل القيم صحيحة):
--   flag_int('true')  = 1     flag_int('false') = 0
--   flag_int('1')     = 1     flag_int('0')     = 0
--   flag_int('"1"')   = 1     flag_int(null)    = 0
