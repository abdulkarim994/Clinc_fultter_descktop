-- 0061 — قراءة تفاصيل الاشتراك للمستخدم (المرحلة د). دالة قراءةٍ بحتة (self)
-- تُكمّل حمولة verify_license بالحقول التي تحتاجها شاشة «الاشتراك والترخيص»:
-- تاريخ التفعيل (starts_at)، بادئة الكود المفعِّل، آخر تحقق، وآخر مزامنة جهاز.
-- لا تلمس verify_license ولا أي منطق إنفاذ — إضافةٌ آمنة.

create or replace function public.get_my_subscription()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  s     public.subscriptions%rowtype;
  v_plan_code text;
  v_plan_name text;
  v_code_prefix text;
  v_last_verified timestamptz;
  v_last_sync timestamptz;
  v_device_count int;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select * into s from public.subscriptions where user_id = v_uid;
  select code, name into v_plan_code, v_plan_name
    from public.plans where id = s.plan_id;

  -- بادئة آخر كودٍ فعّله هذا المستخدم (بلا كشف الكود كاملاً — البادئة فقط).
  select code_prefix into v_code_prefix
    from public.activation_codes
   where bound_user_id = v_uid
   order by used_at desc nulls last
   limit 1;

  select last_seen into v_last_verified
    from public.user_presence where user_id = v_uid;

  select max(last_sync), count(*) filter (where not revoked)
    into v_last_sync, v_device_count
    from public.devices where user_id = v_uid;

  return jsonb_build_object(
    'status',        coalesce(s.status, 'none'),
    'plan_code',     v_plan_code,
    'plan_name',     v_plan_name,
    'trial',         coalesce(s.trial, false),
    'starts_at',     s.starts_at,
    'expires_at',    s.expires_at,
    'code_prefix',   v_code_prefix,
    'last_verified', v_last_verified,
    'last_sync',     v_last_sync,
    'device_count',  coalesce(v_device_count, 0)
  );
end;
$$;

revoke all on function public.get_my_subscription() from public, anon;
grant execute on function public.get_my_subscription() to authenticated;
