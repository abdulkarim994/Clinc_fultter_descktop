-- 0065 — السماح بمفتاح إعداد app_update (المرحلة هـ). العلة: admin_set_config
-- يحصر المفاتيح المسموحة في ('gate','trial','r2','license')، فرفض حفظ
-- «تحديث التطبيق» من اللوحة برسالة «unknown config key: app_update». الإصلاح
-- إضافة 'app_update' للقائمة فقط — بقية الدالة حرفيةٌ كما هي (فحص النوع،
-- الدمج التصحيحي، وتنقيح رمز r2 من التدقيق).

create or replace function public.admin_set_config(p_key text, p_value jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_actor uuid := (select auth.uid());
  v_email text := public._admin_guard();
  v_res   jsonb;
begin
  if p_key not in ('gate','trial','r2','license','app_update') then
    raise exception 'unknown config key: %', p_key using errcode = 'P0001';
  end if;
  if p_value is null or jsonb_typeof(p_value) <> 'object' then
    raise exception 'value must be a json object' using errcode = 'P0001';
  end if;

  insert into app_private.config (key, value, updated_at)
  values (p_key, p_value, now())
  on conflict (key) do update set
    value = app_private.config.value || excluded.value,  -- merge patch onto existing
    updated_at = now()
  returning value into v_res;

  -- Never log secrets: redact r2 token in the audit detail.
  insert into public.admin_audit (actor, actor_email, action, detail)
  values (v_actor, v_email, 'set_config',
          jsonb_build_object('key', p_key,
            'value', case when p_key = 'r2'
                          then (p_value - 'api_token') || jsonb_build_object('api_token','***')
                          else p_value end));
  return v_res;
end;
$function$;

revoke all on function public.admin_set_config(text, jsonb) from public, anon;
grant execute on function public.admin_set_config(text, jsonb) to authenticated;
