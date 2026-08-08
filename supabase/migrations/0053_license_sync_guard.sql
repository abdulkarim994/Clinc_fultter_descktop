-- ============================================================================
-- 0053 — حارس الترخيص في مسار كتابة المزامنة (المرحلة ٥)
-- ============================================================================
--
--  «الأسنان الحقيقية»: شاشة التفعيل في العميل حاجزُ تجربةٍ، وهذا الحارس هو
--  المنع الفعلي — الخادم يرفض كتابة المزامنة لاشتراكٍ منتهٍ/محظور/مجمَّد
--  **حين يكون الإجبار مفعَّلاً**. وبينما gate.enforce=false (الوضع الحالي)
--  يعيد الحارس true دائماً، فسلوك apply_changes مطابقٌ تماماً لما قبله.
--
--  السحب (pull_changes) يبقى مفتوحاً عمداً: بياناته للمالك وحده، وحجبها لا
--  يمنع إساءة بل يعيق مالكاً منتهياً عن رؤية بياناته — والمنع في الكتابة.

create or replace function public.license_allows_sync(p_uid uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $$
  select case
    when not coalesce(
      (select (value->>'enforce')::boolean
         from app_private.config where key = 'gate'), false)
      then true                              -- الإجبار مطفأ ⇒ اسمح دائماً
    else exists (
      select 1 from public.subscriptions s
       where s.user_id = p_uid
         and s.status in ('active', 'trial')
         and (s.expires_at is null or s.expires_at > now())
    )
  end;
$$;

revoke all on function public.license_allows_sync(uuid) from public, anon;
grant execute on function public.license_allows_sync(uuid) to authenticated;

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
begin
  if v_uid is null then
    raise exception 'apply_changes: not authenticated';
  end if;

  -- م135 — حارس الترخيص (المرحلة ٥): يمنع كتابة المزامنة لاشتراكٍ غير فعّال
  -- **حين يكون الإجبار مفعَّلاً فقط**. الدالة تعيد true دائماً بينما
  -- gate.enforce=false، فالسلوك الآن مطابقٌ تماماً لما قبله (متحقَّق).
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
$function$
