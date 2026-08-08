-- ============================================================================
--  0023 — تطبيع أعلام JSON المنطقية إلى أعداد في sync_rows
--
--  ✅ نُفِّذ على الإنتاج: 2026-07-31
--     · 7 صفوف (كلها prosthetics) — 4 بـtrue و3 بـfalse
--     · النسخة الاحتياطية: public._bool_flags_backup_20260731
--     · تحقّق صفّاً صفّاً: عدد المفاتيح ثابت، وبقية الحقول متطابقة تماماً
--     · النتيجة: صفر منطقي في 426 صفاً، و::int ينجح على الجدول كلّه
--
--  ⚠ يجب **إعادة تشغيله بعد إطلاق العميل المتضمّن م76**: التنظيف تمّ قبل
--    الإطلاق (بطلب المالك)، والعميل الحالي في الميدان ما زال يكتب منطقياً
--    من مسار التركيبات حتى يُحدَّث. راقب بـ`select * from flag_type_audit();`
-- ============================================================================
--
--  العلة (الخادم)
--  ──────────────
--  `payload->>'isDebt'` يُرجع **نصّ** قيمة JSON، فمنطقي JSON يصير 'true' أو
--  'false' ويرفضه التحويل `::int` بالخطأ:
--
--      ERROR: 22P02: invalid input syntax for type integer: "true"
--
--  و`get_monthly_summary` وأمثالها تجمّع بـ`(payload->>'isDebt')::int`،
--  فصفٌّ واحد فاسد **يُسقط التقرير كلّه لا سطراً منه**.
--
--  المصدر (العميل — أُصلح في م76)
--  ──────────────────────────────
--  كان `record_saver.dart` يكتب `'isDebt': f.isDebt` منطقيةً خاماً في مسار
--  التركيبات. الحقل عمودٌ مرقّى في `records` (فينقذه مُقيّد SQLite صامتاً)
--  ولا عمود له في `prosthetics` ⇒ يذهب إلى كتلة `data` منطقياً ويُدفع كما هو.
--  ولهذا كانت الإصابة **محصورة في `prosthetics`**، وهو ما ضلّل الفحص السابق:
--  فُحص `records` فوُجد نظيفاً فاستُنتج أن العميل سليم.
--
--  ⚠ الترتيب إلزامي: أطلق نسخة العميل المتضمّنة م76 **قبل** هذه المهاجرة.
--    التنظيف قبل الإصلاح يعالج العَرَض ويترك المصدر ينزف صفوفاً جديدة —
--    وهو بالضبط ما حدث في تنظيف 2026-07-30.
--
--  خصائص هذا السكربت
--  ──────────────────
--   • عديم الأثر (idempotent): إعادة تشغيله بلا صفوف مطابقة = صفر تغيير.
--   • لا يلمس `updated_at` ولا `_hlc` ولا `server_seq`: التطبيع تصحيح نوع
--     لا تحرير محتوى، ورفع الساعة كان سيجعل الخادم يهزم تعديلات محلية
--     أحدث على الأجهزة، ويُشعل دورة دفع في كل جهاز بلا سبب.
--   • يُبقي نسخة احتياطية من الصفوف المعدَّلة قبل المسّ.
-- ============================================================================

begin;

-- ── الأعلام المعنيّة: كل ما تُحوّله الدوال إلى عدد صحيح ──────────────────
create temporary table _flag_keys(k text) on commit drop;
insert into _flag_keys(k) values ('isDebt'), ('isPros'), ('isDebtPayment');

-- ── ١. لقطة قبل/بعد للمراجعة والتراجع ────────────────────────────────────
create table if not exists public._bool_flags_backup_20260730 (
  user_id   uuid,
  entity    text,
  id        text,
  payload   jsonb,
  backed_up timestamptz not null default now()
);
alter table public._bool_flags_backup_20260730 enable row level security;

insert into public._bool_flags_backup_20260730 (user_id, entity, id, payload)
select r.user_id, r.entity, r.id, r.payload
  from sync_rows r
 where exists (select 1 from _flag_keys f
                where jsonb_typeof(r.payload -> f.k) = 'boolean');

-- ── ٢. التقرير قبل التنفيذ ───────────────────────────────────────────────
do $$
declare v_rows bigint; v_fields bigint;
begin
  select count(distinct (r.user_id, r.entity, r.id)), count(*)
    into v_rows, v_fields
    from sync_rows r
    join _flag_keys f on jsonb_typeof(r.payload -> f.k) = 'boolean';
  raise notice 'قبل التطبيع: % صفاً، % حقلاً منطقياً', v_rows, v_fields;
end $$;

-- ── ٣. التطبيع: منطقي ⇒ 0/1، وما عداه لا يُمسّ ───────────────────────────
--    jsonb_set لكل مفتاح على حدة، والشرط داخل الاستعلام يضمن أن الصفوف
--    السليمة لا تدخل UPDATE أصلاً (لا write amplification على 419 صفاً).
update sync_rows r
   set payload = (
         select coalesce(
                  (select jsonb_object_agg(
                            e.key,
                            case
                              when e.key in ('isDebt','isPros','isDebtPayment')
                                   and jsonb_typeof(e.value) = 'boolean'
                              then to_jsonb(case when e.value = 'true'::jsonb
                                                 then 1 else 0 end)
                              else e.value
                            end)
                     from jsonb_each(r.payload) e),
                  r.payload)
       )
 where exists (select 1 from _flag_keys f
                where jsonb_typeof(r.payload -> f.k) = 'boolean');

-- ── ٤. التحقق: يفشل الالتزام كلّه إن بقي منطقي واحد ──────────────────────
do $$
declare v_left bigint;
begin
  select count(*) into v_left
    from sync_rows r
    join _flag_keys f on jsonb_typeof(r.payload -> f.k) = 'boolean';
  if v_left > 0 then
    raise exception 'بقي % حقلاً منطقياً بعد التطبيع — أُلغيت المهاجرة', v_left;
  end if;
  raise notice 'بعد التطبيع: صفر حقل منطقي ✓';
end $$;

-- ── ٥. الإثبات الموجب: التحويل الذي كان يفشل صار يعمل على كل الصفوف ──────
do $$
declare v_sum bigint;
begin
  select coalesce(sum((payload->>'isDebt')::int), 0) into v_sum
    from sync_rows where payload ? 'isDebt';
  raise notice 'اجتاز ::int على كل الصفوف (مجموع isDebt = %)', v_sum;
end $$;

commit;

-- ============================================================================
--  بعد التحقق من سلامة التقارير، أسقط النسخة الاحتياطية:
--      drop table public._bool_flags_backup_20260730;
--
--  حارس دائم اختياري — يمنع عودة الفئة من أي عميل، بأي جيل:
--
--      alter table sync_rows add constraint sync_rows_flags_not_boolean
--        check (
--          jsonb_typeof(payload -> 'isDebt')        is distinct from 'boolean'
--          and jsonb_typeof(payload -> 'isPros')    is distinct from 'boolean'
--          and jsonb_typeof(payload -> 'isDebtPayment')
--                                                   is distinct from 'boolean'
--        ) not valid;
--      alter table sync_rows validate constraint sync_rows_flags_not_boolean;
--
--  ⚠ وزن القرار: القيد يجعل `apply_changes` **يرفض** دفعة العميل القديم بدل
--    قبولها فاسدةً. هذا هو السلوك الصحيح، لكنه يعني أن أي جهاز لم يُحدَّث
--    إلى م76 ستفشل مزامنته للتركيبات — وستظهر صفوفه في الحجْر بعد ثماني
--    محاولات. لا تُفعّله إلا بعد التأكد من تحديث كل الأجهزة.
-- ============================================================================
