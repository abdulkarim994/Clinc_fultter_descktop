-- م81 — حارس الجهاز الغائب لتطهير شواهد القبور.
--
--  العلة: إحياء المحذوفات
--  ──────────────────────
--  `purge_expired` تحذف الشواهد **بالعمر وحده**. وجهاز غاب أطول من مدّة
--  الاحتفاظ لا يعلم بالحذف أبداً: صفّه المحلي حيّ ومؤهَّل للدفع، فإذا عاد
--  لم يجد الخادم صفّاً (طُهِّر) فيُدرجه من جديد — **فيعود السجلّ المحذوف
--  وينتشر على كل الأجهزة**.
--
--  والمفارقة أن `device_sync_state` موجود منذ المهاجرة 0022 ويحرس الأرشفة
--  فعلاً — لكن التطهير لم يكن يستشيره. هذه المهاجرة تُطبّق الحارس نفسه.
--
--  القاعدة
--  ───────
--  لا يُطهَّر شاهدٌ إلا إذا اجتمع شرطان:
--    ١) مضى عليه أكثر من مدّة الاحتفاظ (كما كان)، **و**
--    ٢) `txid` أقل من **أدنى مؤشّر** بين الأجهزة النشطة — أي أن كل جهاز
--       نشط رآه فعلاً.
--
--  والأجهزة **المهجورة** تُستثنى من الحساب (لم تظهر منذ `p_abandon_days`،
--  افتراضياً 180 يوماً) كي لا يُوقف لوحٌ تالف التطهيرَ إلى الأبد — نفس
--  المنطق والافتراض المستعملان في `archive_rows`.
--
--  وحين لا يوجد أي جهاز مسجَّل (حساب جديد أو عميل قديم لا يبلّغ مؤشّره)
--  يعود السلوك إلى **العمر وحده**: لا نُعطّل التطهير على من لم يُحدِّث بعد،
--  ولا نُغيّر سلوك عميل قائم بلا إنذار.
--
--  التوافق: التوقيع يكسب معاملاً اختيارياً واحداً. النداء القديم بمعامل
--  واحد ما زال صالحاً ويكسب الحماية تلقائياً.

create or replace function public.purge_expired(
  p_retain_days   integer default 7,
  p_abandon_days  integer default 180
)
returns jsonb
language plpgsql
security definer
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_uid        uuid := auth.uid();
  v_min_cursor bigint;
  v_devices    int;
  n            int;
begin
  if v_uid is null then
    raise exception 'غير مصادَق';
  end if;

  -- أدنى مؤشّر بين الأجهزة النشطة وحدها.
  select count(*), min(cursor_txid)
    into v_devices, v_min_cursor
    from public.device_sync_state
   where user_id = v_uid
     and last_seen_at > now() - make_interval(days => greatest(coalesce(p_abandon_days, 180), 1));

  delete from sync_rows
   where user_id = v_uid
     and _deleted = true
     and updated_at <
         now() - make_interval(days => greatest(coalesce(p_retain_days, 7), 7))
     -- الحارس: يُطبَّق فقط حين يوجد جهاز نشط مسجَّل.
     and (v_devices = 0 or txid < coalesce(v_min_cursor, 0));

  get diagnostics n = row_count;

  return jsonb_build_object(
    'purged', n,
    'active_devices', v_devices,
    'min_cursor', v_min_cursor
  );
end;
$function$;

comment on function public.purge_expired(integer, integer) is
  'م81 — تطهير الشواهد بالعمر + حارس أدنى مؤشّر جهاز نشط (يمنع إحياء المحذوفات).';

revoke all on function public.purge_expired(integer, integer) from public, anon;
grant execute on function public.purge_expired(integer, integer) to authenticated, service_role;

-- ⚠ إسقاط النسخة القديمة **إلزامي** — نُفِّذ على الإنتاج 2026-07-31:
--
--     drop function if exists public.purge_expired(integer);
--
-- بدونه تبقى النسخة ذات المعامل الواحد موجودة، ويصيبها استدعاء العميل
-- (`{'p_retain_days': n}`) فيعمل التطهير **بلا حارس** — والإصلاح يبدو
-- مُطبَّقاً وهو معطَّل. رُصد بفحص التوقيعات بعد التطبيق لا قبله.
--
-- تحقّق: استدعاء بمعامل مُسمّى واحد يصيب النسخة ذات المعاملين ويستعمل
-- الافتراضي للثاني (مُثبَت على الإنتاج).
