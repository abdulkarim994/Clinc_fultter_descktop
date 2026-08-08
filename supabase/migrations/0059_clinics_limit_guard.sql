-- 0059 — حارس عدد العيادات على الخادم (المرحلة ب). العيادات تُخزَّن مصفوفةً
-- داخل صفّ الإعدادات app.config (كيان settings)، فالإنفاذ يكون عند تطبيق ذلك
-- الصف في apply_changes: إن تجاوز عددُها max_clinics الفعّال رُفضت الكتابة.
--
-- سلامة الإنتاج (قرار المالك): خلف مفتاح فرعي مستقل gate.enforce_clinics
-- يبدأ **مطفأً** — فلا حجب جديد؛ بل قياسٌ (مرة/ساعة/مستخدم) لمن سيتجاوز.
--
-- apply_changes يعمل بصلاحية المستخدم (لا SECURITY DEFINER) فلا يقرأ
-- app_private.config ولا يكتب admin_audit؛ لذا كل ذلك داخل دالة الحارس
-- SECURITY DEFINER أدناه، وapply_changes يناديها فقط.

-- المفتاح الفرعي: مطفأ افتراضاً (لا نلمس enforce العام ولا enforce_storage).
insert into app_private.config (key, value)
values ('gate', jsonb_build_object('enforce_clinics', false))
on conflict (key) do update
  set value = app_private.config.value
    || jsonb_build_object(
         'enforce_clinics',
         coalesce(app_private.config.value->'enforce_clinics', 'false'::jsonb));

-- حارس العيادات: يقرّر الحجب ويسجّل القياس. يعيد block=true فقط حين
-- (تجاوزٌ فعلي) و(المفتاح مفعّل). max_clinics غير معرّف/صفر ⇒ بلا حدّ.
create or replace function public.clinics_guard(p_uid uuid, p_count integer)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_max     int := nullif(public.effective_features(p_uid)->>'max_clinics', '')::int;
  v_enf     boolean := coalesce(
              (select (value->>'enforce_clinics')::boolean
                 from app_private.config where key = 'gate'), false);
  v_over    boolean := (v_max is not null and v_max > 0 and p_count > v_max);
  v_email   text;
  v_recent  boolean;
begin
  if v_over and not v_enf then
    select exists(
      select 1 from public.admin_audit
       where action = 'clinics_over_probe' and target_user = p_uid
         and created_at > now() - interval '1 hour'
    ) into v_recent;
    if not v_recent then
      select email into v_email from auth.users where id = p_uid;
      insert into public.admin_audit
        (actor, actor_email, action, target_user, target_email, detail)
      values (p_uid, v_email, 'clinics_over_probe', p_uid, v_email,
              jsonb_build_object('count', p_count, 'max', v_max));
    end if;
  end if;
  return jsonb_build_object(
    'block',   v_over and v_enf,
    'over',    v_over,
    'count',   p_count,
    'max',     v_max,
    'enforced', v_enf
  );
end;
$$;

revoke all on function public.clinics_guard(uuid, integer) from public, anon;
grant execute on function public.clinics_guard(uuid, integer) to authenticated;

-- apply_changes: منسوخةٌ حرفياً من 0053 مع إضافة فحص العيادات وحده عند صفّ
-- settings/app.config. لا تغيير آخر في المنطق.
CREATE OR REPLACE FUNCTION public.apply_changes(ops jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
declare
  v_uid     uuid := auth.uid();
  op        jsonb;
  v_opid    text; v_entity text; v_action text; v_id text; v_hlc text;
  v_payload jsonb; v_clinic text; v_origin text;
  cur       sync_rows%rowtype;
  fin       sync_rows%rowtype;
  did_apply boolean;
  results   jsonb := '[]'::jsonb;
  v_cc      int;
  v_guard   jsonb;
begin
  if v_uid is null then
    raise exception 'apply_changes: not authenticated';
  end if;

  -- م135 — حارس الترخيص (المرحلة ٥): يمنع كتابة المزامنة لاشتراكٍ غير فعّال
  -- **حين يكون الإجبار مفعَّلاً فقط**.
  if not public.license_allows_sync(v_uid) then
    raise exception 'license: subscription inactive — activate to sync'
      using errcode = 'P0001';
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

    -- المرحلة ب — حارس عدد العيادات: صفّ الإعدادات app.config يحمل مصفوفة
    -- clinics. حين يتجاوز عددُها الحدَّ والمفتاح مفعّل تُرفض الدفعة كلها
    -- (عميلٌ سليم لا يرسل تجاوزاً لأن الواجهة تمنعه؛ فهذا صدٌّ لعميلٍ معدَّل).
    if v_entity = 'settings' and v_id = 'app.config' and v_action <> 'delete'
       and jsonb_typeof(v_payload->'value'->'clinics') = 'array' then
      v_cc := jsonb_array_length(v_payload->'value'->'clinics');
      v_guard := public.clinics_guard(v_uid, v_cc);
      if (v_guard->>'block')::boolean then
        raise exception 'clinics_over_limit: % of %',
          v_guard->>'count', v_guard->>'max' using errcode = 'P0001';
      end if;
    end if;

    -- م84 — قصّ الختم المستقبلي البعيد.
    v_hlc := public.hlc_clamp_future(v_hlc);
    if v_payload ? '_hlc' then
      v_payload := jsonb_set(v_payload, '{_hlc}', to_jsonb(v_hlc));
    end if;

    if v_opid is not null and exists (select 1 from applied_ops where op_id = v_opid) then
      select * into fin from sync_rows where user_id = v_uid and entity = v_entity and id = v_id;
      results := results || jsonb_build_object(
        'op_id', v_opid, 'entity', v_entity, 'id', v_id,
        'server_seq', fin.server_seq, 'applied_hlc', fin._hlc, 'skipped', true);
      continue;
    end if;

    select * into cur from sync_rows where user_id = v_uid and entity = v_entity and id = v_id;
    did_apply := false;

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
