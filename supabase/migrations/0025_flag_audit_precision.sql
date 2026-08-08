-- ============================================================================
--  0025 — ضبط دقّة أداة رصد تلوّث الأنواع
--  ⚠ مُطبَّقة على الإنتاج: 2026-07-31 (version 20260731005106)
-- ============================================================================
--
--  لماذا تعديل أداة وُلدت قبل دقائق
--  ────────────────────────────────
--  أول تشغيل لـ`flag_type_audit` أبلغ عن **59 صفّاً** تحمل `isDebtPayment`
--  بقيمة JSON `null`. والفحص أثبت أنها **حميدة تماماً**:
--
--    • المسار القديم: `coalesce((payload->>'isDebtPayment')::int, 0)`
--      — المعامل `->>` يُرجع SQL NULL، و`NULL::int` لا يرمي، وcoalesce ⇒ 0.
--    • المسار الجديد: `flag_int` يقرأ نوع 'null' ⇒ 0.
--
--  فالنتيجة صفر في الحالتين، ولا رمي ولا سوء قراءة. ومصدرها طبيعي: عمود
--  اختياري غير مضبوط يسافر NULL.
--
--  وأداة رصد تُنذر بما لا يضرّ **تُهمَل بعد أسبوع**، فتصير أسوأ من لا أداة —
--  وهو المبدأ نفسه الذي جعلنا نُخرج خطوة التنسيق من حواجز CI. لذلك تُحصر
--  الإنذارات في الأنواع التي تكسر `::int` فعلاً:
--
--    boolean       ← علّة م76 بعينها (22P02)
--    string        ← يمرّ إن كان "1" ويكسر إن كان "نعم"
--    object/array  ← يكسر دائماً
--
--  ويُستثنى `null` عمداً.
--
--  القاعدة الناتجة: **نتيجة فارغة = سليم. أي صفّ = فعل مطلوب.**

drop function if exists public.flag_type_audit();

create function public.flag_type_audit()
returns table(entity text, flag text, json_type text, rows bigint,
              newest timestamptz, breaks_int_cast boolean)
language sql
stable
set search_path to 'public', 'extensions', 'pg_temp'
as $$
  select r.entity,
         f.k as flag,
         jsonb_typeof(r.payload -> f.k) as json_type,
         count(*) as rows,
         max(r.updated_at) as newest,
         -- هل يُسقِط هذا النوع تقريراً يستعمل (payload->>k)::int الهشّ؟
         bool_or(jsonb_typeof(r.payload -> f.k) <> 'string'
                 or (r.payload ->> f.k) !~ '^-?[0-9]+$') as breaks_int_cast
    from sync_rows r
    cross join (values ('isDebt'),('isPros'),('isDebtPayment')) as f(k)
   where r.payload ? f.k
     and jsonb_typeof(r.payload -> f.k) not in ('number', 'null')
   group by 1,2,3
   order by 4 desc
$$;

comment on function public.flag_type_audit() is
  'م77 — يُرجع صفوفاً إن عاد تلوّث أنواع الأعلام. النتيجة الفارغة = سليم. JSON null مستثنى عمداً (يُقرأ صفراً بلا رمي).';

revoke all on function public.flag_type_audit() from public, anon;
grant execute on function public.flag_type_audit() to authenticated, service_role;

-- ── الاستعمال الدوري ────────────────────────────────────────────────────
--   select * from flag_type_audit();          -- فارغ = سليم
--
-- شغّله بعد كل إطلاق عميل جديد، وبعد أي ترحيل من جيل عميل آخر.
