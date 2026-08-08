-- ============================================================================
--  م84 — قصّ الختم المستقبلي البعيد عند الاستقبال في apply_changes
-- ============================================================================
--
--  العلّة (رُصدت بالتشغيل في تدقيق م84)
--  ────────────────────────────────────
--  جهازٌ بساعةٍ خاطئة يدفع صفاً بختم HLC في المستقبل البعيد (سنة 2100
--  مثلاً). حارسُ LWW — `hlc_is_newer(v_hlc, cur._hlc)` — لا يعرف حداً
--  للمعقولية، فيقبله. ومنذ تلك اللحظة **يُحجَب كل تعديلٍ سليمٍ لاحق** على
--  ذلك الصف بصمت: ختمُه الحاضر (2026) أصغر من المسموم (2100)، فيردّه
--  الخادم-لكن-يُقرّه، فيمسح العميلُ علمَ الاتساخ ويظنّ نفسه متزامناً. صفُّ
--  المريض عالقٌ على القيمة المسمومة عبر كل الأجهزة حتى تبلغ ساعةُ الحائط
--  ذلك الزمن — أي عملياً إلى الأبد.
--
--  والعميل يحمي ساعته المنطقية من هذا الانحراف (م77)، لكن ذلك يحمي الساعة
--  لا الصف: الختم المسموم يبقى مخزَّناً على الخادم يحجب ما بعده.
--
--  العلاج: القصّ عند المصدر
--  ────────────────────────
--  عند الاستقبال، أيُّ ختمٍ تتجاوز أجزاؤه الزمنية «الآن + حدّ الانحراف
--  (24 ساعة)» يُقصّ زمنُه إلى ذلك السقف، مع إبقاء العدّاد والجهاز. فالصف
--  يَلحق بالحاضر لا بالمستقبل: لا تلوّث، ولا فقدُ بيانات (الصف يُحفظ)،
--  ولا حجبٌ لِما بعده. وهي القاعدة القياسية لاستقبال HLC.
--
--  والقصّ يشفي أيضاً صفاً مسموماً قائماً: بما أن الختم المخزَّن صار محدوداً
--  بالحاضر، فأولُ تعديلٍ سليمٍ لاحق يتجاوزه فيُطبَّق. (قاعدة اليوم خاليةٌ
--  من التسمّم أصلاً — مستخدمان اختباريان لا بيانات — فهذا وقايةٌ لِما بعد.)
--
--  الأمان: تغييرٌ جراحيّ. `hlc_clamp_future` دالةٌ نقيّة جديدة، و
--  `apply_changes` يُعاد تعريفها بمنطقها نفسه حرفياً عدا سطرَ حساب الختم
--  الفعّال. لا مساس بالمخطّط ولا بأي صفّ قائم.

-- ── دالة القصّ: نقيّة، تُرجع الختم كما هو إن كان ضمن الحدّ ──────────────────
create or replace function public.hlc_clamp_future(h text)
returns text
language plpgsql
immutable
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  ms      bigint;
  ceiling bigint;
begin
  if h is null or h = '' then return h; end if;
  ms := nullif(split_part(h, ':', 1), '')::bigint;
  if ms is null then return h; end if;
  -- الحدّ: الآن (ملي ثانية) + 24 ساعة، مطابقٌ لـkMaxClockDriftMs في العميل.
  ceiling := (extract(epoch from now()) * 1000)::bigint + 86400000;
  if ms <= ceiling then return h; end if;
  -- القصّ إلى **الآن** لا إلى السقف: القصّ إلى (الآن+الحدّ) يترك الختم في
  -- المستقبل 24 ساعة فيظلّ يحجب التعديلات يوماً كاملاً. الكشف بالسقف،
  -- والهبوط إلى الحاضر.
  return ((extract(epoch from now()) * 1000)::bigint)::text || ':' ||
         coalesce(nullif(split_part(h, ':', 2), ''), '0') || ':' ||
         split_part(h, ':', 3);
end;
$function$;

-- ── apply_changes: نسخة م84 — تقصّ الختم قبل المقارنة والتخزين ─────────────
create or replace function public.apply_changes(ops jsonb)
returns jsonb
language plpgsql
set search_path to 'public', 'extensions', 'pg_temp'
as $function$
declare
  v_uid     uuid := auth.uid();
  op        jsonb;
  v_opid    text; v_entity text; v_action text; v_id text; v_hlc text;
  v_payload jsonb; v_clinic text; v_origin text;
  cur       sync_rows%rowtype;
  fin       sync_rows%rowtype;
  did_apply boolean;
  results   jsonb := '[]'::jsonb;
begin
  if v_uid is null then
    raise exception 'apply_changes: not authenticated';
  end if;

  for op in select value from jsonb_array_elements(coalesce(ops, '[]'::jsonb)) as t(value) loop
    v_opid    := op->>'op_id';
    v_entity  := op->>'entity';
    v_action  := coalesce(op->>'action', 'upsert');
    v_payload := coalesce(op->'row', '{}'::jsonb);
    v_id      := coalesce(op->>'id',  v_payload->>'id');
    v_hlc     := coalesce(op->>'hlc', v_payload->>'_hlc');
    v_clinic  := v_payload->>'clinic_id';
    v_origin  := v_payload->>'_origin';

    if v_entity is null or v_id is null then
      continue; -- malformed op; skip defensively
    end if;

    -- م84 — قصّ الختم المستقبلي البعيد، وكتابته في الحمولة كي يقرأه
    -- العميل متّسقاً عند السحب. كل ما بعده يستعمل الختم المقصوص.
    v_hlc := public.hlc_clamp_future(v_hlc);
    if v_payload ? '_hlc' then
      v_payload := jsonb_set(v_payload, '{_hlc}', to_jsonb(v_hlc));
    end if;

    -- Idempotency: a replayed op is a no-op; still return current state.
    if v_opid is not null and exists (select 1 from applied_ops where op_id = v_opid) then
      select * into fin from sync_rows where user_id = v_uid and entity = v_entity and id = v_id;
      results := results || jsonb_build_object(
        'op_id', v_opid, 'entity', v_entity, 'id', v_id,
        'server_seq', fin.server_seq, 'applied_hlc', fin._hlc, 'skipped', true);
      continue;
    end if;

    select * into cur from sync_rows where user_id = v_uid and entity = v_entity and id = v_id;
    did_apply := false;

    -- Apply if new, strictly newer by HLC, or healing a stored future-poison
    -- with a now-plausible stamp (cur is beyond the drift ceiling, v is not).
    if not found
       or hlc_is_newer(v_hlc, cur._hlc)
       or (cur._hlc is distinct from public.hlc_clamp_future(cur._hlc)
           and v_hlc = public.hlc_clamp_future(v_hlc)) then
      insert into sync_rows (user_id, entity, id, payload, clinic_id, _hlc, _deleted, _origin)
      values (v_uid, v_entity, v_id, v_payload, v_clinic, v_hlc, (v_action = 'delete'), v_origin)
      on conflict (user_id, entity, id) do update
        set payload   = excluded.payload,
            clinic_id = excluded.clinic_id,
            _hlc      = excluded._hlc,
            _deleted  = excluded._deleted,
            _origin   = excluded._origin;
      did_apply := true;
    end if;

    if v_opid is not null then
      insert into applied_ops (user_id, op_id) values (v_uid, v_opid)
      on conflict (op_id) do nothing;
    end if;

    select * into fin from sync_rows where user_id = v_uid and entity = v_entity and id = v_id;
    results := results || jsonb_build_object(
      'op_id', v_opid, 'entity', v_entity, 'id', v_id,
      'server_seq', fin.server_seq, 'applied_hlc', fin._hlc, 'applied', did_apply);
  end loop;

  return jsonb_build_object('results', results);
end;
$function$;
