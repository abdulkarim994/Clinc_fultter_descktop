-- 0060 — حد الأجهزة وإدارتها (المرحلة ج).
--  • أعمدة أغنى للجهاز: brand · os_version · last_sync.
--  • verify_license (نسخة النظام المعتمد + إضافات): يلتقط brand/os_version،
--    يختم last_sync، ويحسم قرار الأجهزة خلف مفتاح gate.enforce_devices
--    (مطفأ = قياس device_over_probe؛ مفعّل = device_block=true للجهاز الزائد)،
--    ويصدّر device_block/device_enforced/device_count/max_devices للعميل.
--  • admin_user_devices: يعيد الحقول الأغنى + حالة نصية.
--  • admin_reset_devices: إبطال كل أجهزة مستخدم (يسمح بتسجيل جهازٍ جديد نظيف).
--
-- الإنفاذ الفعلي بوابةٌ في العميل (كحارس التفعيل تماماً): verify_license يعيد
-- device_block فيقفز التطبيق لشاشة «تجاوز حد الأجهزة». زيادة الحد من اللوحة
-- عبر admin_set_features (max_devices) القائم.

alter table public.devices add column if not exists brand text;
alter table public.devices add column if not exists os_version text;
alter table public.devices add column if not exists last_sync timestamptz;

insert into app_private.config (key, value)
values ('gate', jsonb_build_object('enforce_devices', false))
on conflict (key) do update
  set value = app_private.config.value
    || jsonb_build_object(
         'enforce_devices',
         coalesce(app_private.config.value->'enforce_devices', 'false'::jsonb));

-- قائمة أجهزة المستخدم للّوحة — أغنى + حالة.
create or replace function public.admin_user_devices(p_user uuid)
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'id',          d.id,
        'device_id',   d.device_id,
        'platform',    d.platform,
        'model',       d.model,
        'brand',       d.brand,
        'os_version',  d.os_version,
        'app_version', d.app_version,
        'first_seen',  d.first_seen,
        'last_seen',   d.last_seen,
        'last_sync',   d.last_sync,
        'revoked',     d.revoked,
        'status',      case when d.revoked then 'revoked' else 'active' end
      ) order by d.revoked asc, d.last_seen desc nulls last)
    from public.devices d
    where d.user_id = p_user
  ), '[]'::jsonb);
end;
$$;
revoke all on function public.admin_user_devices(uuid) from public, anon;
grant execute on function public.admin_user_devices(uuid) to authenticated;

-- إعادة تعيين الأجهزة — إبطال الكل (تسجيلٌ نظيف عند التحقق التالي) + تدقيق.
create or replace function public.admin_reset_devices(p_user uuid)
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_email text := public._admin_guard();
  v_target text;
  v_n int;
begin
  select email into v_target from auth.users where id = p_user;
  update public.devices set revoked = true where user_id = p_user and revoked = false;
  get diagnostics v_n = row_count;
  insert into public.admin_audit
    (actor, actor_email, action, target_user, target_email, detail)
  values (v_actor, v_email, 'devices_reset', p_user, v_target,
          jsonb_build_object('revoked_count', v_n));
  return v_n;
end;
$$;
revoke all on function public.admin_reset_devices(uuid) from public, anon;
grant execute on function public.admin_reset_devices(uuid) to authenticated;

-- verify_license — نسخة النظام المعتمد حرفياً + إضافات المرحلة ج المعلّمة.
create or replace function public.verify_license(p_device jsonb)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  v_uid        uuid := (select auth.uid());
  v_device_id  text := nullif(p_device->>'device_id', '');
  v_platform   text := nullif(p_device->>'platform', '');
  v_model      text := nullif(p_device->>'model', '');
  v_app_ver    text := nullif(p_device->>'app_version', '');
  v_brand      text := nullif(p_device->>'brand', '');        -- م ج
  v_os_ver     text := nullif(p_device->>'os_version', '');   -- م ج

  v_gate       jsonb;
  v_trial_cfg  jsonb;
  v_enforce    boolean;
  v_trial_en   boolean;
  v_trial_days int;

  s            public.subscriptions%rowtype;
  v_had_paid   boolean;
  v_trial_plan public.plans%rowtype;
  v_plan_code  text;
  v_eff        jsonb;
  v_max_dev    int;
  v_dev_count  int;
  v_dev_allow  boolean;
  v_dev_enf    boolean;   -- م ج: مفتاح enforce_devices
  v_dev_block  boolean;   -- م ج: القرار النهائي للعميل
  v_recent     boolean;   -- م ج: منع إغراق القياس

  v_used       bigint := 0;
  v_quota      bigint;
  v_files      int := 0;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  select value into v_gate      from app_private.config where key = 'gate';
  select value into v_trial_cfg from app_private.config where key = 'trial';
  v_enforce    := coalesce((v_gate->>'enforce')::boolean, false);
  v_trial_en   := coalesce((v_trial_cfg->>'enabled')::boolean, false);
  v_trial_days := coalesce((v_trial_cfg->>'days')::int, 14);

  -- device upsert (register / refresh) — + brand/os_version/last_sync (م ج)
  if v_device_id is not null then
    insert into public.devices (user_id, device_id, platform, model, brand,
                                os_version, app_version, first_seen, last_seen, last_sync)
    values (v_uid, v_device_id, v_platform, v_model, v_brand, v_os_ver,
            v_app_ver, now(), now(), now())
    on conflict (user_id, device_id) do update set
      platform    = coalesce(excluded.platform,    public.devices.platform),
      model       = coalesce(excluded.model,       public.devices.model),
      brand       = coalesce(excluded.brand,       public.devices.brand),
      os_version  = coalesce(excluded.os_version,  public.devices.os_version),
      app_version = coalesce(excluded.app_version, public.devices.app_version),
      last_seen   = now(),
      last_sync   = now();
  end if;

  insert into public.user_presence (user_id, last_seen, app_version, platform, updated_at)
  values (v_uid, now(), v_app_ver, v_platform, now())
  on conflict (user_id) do update set
    last_seen   = now(),
    app_version = coalesce(excluded.app_version, public.user_presence.app_version),
    platform    = coalesce(excluded.platform,    public.user_presence.platform),
    updated_at  = now();

  select * into s from public.subscriptions where user_id = v_uid;

  if (s.user_id is null or s.status = 'none') and v_trial_en then
    select not exists (
      select 1 from public.activation_codes c where c.bound_user_id = v_uid
    ) into v_had_paid;
    if v_had_paid then
      select * into v_trial_plan from public.plans where code = 'trial';
      insert into public.subscriptions
        (user_id, plan_id, status, starts_at, expires_at, trial, features, limits_override)
      values
        (v_uid, v_trial_plan.id, 'trial', now(),
         now() + make_interval(days => v_trial_days), true, '{}'::jsonb, '{}'::jsonb)
      on conflict (user_id) do update set
        plan_id    = excluded.plan_id,
        status     = 'trial',
        starts_at  = coalesce(public.subscriptions.starts_at, excluded.starts_at),
        expires_at = excluded.expires_at,
        trial      = true,
        updated_at = now();
      select * into s from public.subscriptions where user_id = v_uid;
    end if;
  end if;

  if s.user_id is not null
     and s.status in ('active','trial')
     and s.expires_at is not null
     and s.expires_at < now() then
    update public.subscriptions
       set status = 'expired', updated_at = now()
     where user_id = v_uid;
    select * into s from public.subscriptions where user_id = v_uid;
  end if;

  select code into v_plan_code from public.plans where id = s.plan_id;
  v_eff := coalesce(public.effective_features(v_uid), '{}'::jsonb);

  -- Device allowance + قرار الإنفاذ (م ج)
  v_max_dev := nullif(v_eff->>'max_devices', '')::int;
  select count(*) into v_dev_count
    from public.devices
   where user_id = v_uid and revoked = false;
  v_dev_allow := (v_max_dev is null) or (v_dev_count <= v_max_dev);
  v_dev_enf   := coalesce((v_gate->>'enforce_devices')::boolean, false);
  v_dev_block := v_dev_enf and not v_dev_allow;

  -- قياس فقط حين سيُحجب ولمّا يُفعَّل — مرة/ساعة/مستخدم.
  if (not v_dev_allow) and (not v_dev_enf) then
    select exists(
      select 1 from public.admin_audit
       where action = 'device_over_probe' and target_user = v_uid
         and created_at > now() - interval '1 hour'
    ) into v_recent;
    if not v_recent then
      insert into public.admin_audit
        (actor, actor_email, action, target_user, target_email, detail)
      values (v_uid, (select email from auth.users where id = v_uid),
              'device_over_probe', v_uid,
              (select email from auth.users where id = v_uid),
              jsonb_build_object('devices', v_dev_count, 'max', v_max_dev));
    end if;
  end if;

  select used_bytes, quota_bytes, file_count
    into v_used, v_quota, v_files
    from public.storage_usage where user_id = v_uid;
  v_used  := coalesce(v_used, 0);
  v_files := coalesce(v_files, 0);
  if v_quota is null and (v_eff ? 'storage_mb') then
    v_quota := (v_eff->>'storage_mb')::bigint * 1024 * 1024;
  end if;

  return jsonb_build_object(
    'enforce',        v_enforce,
    'status',         coalesce(s.status, 'none'),
    'plan_code',      v_plan_code,
    'features',       v_eff,
    'expires_at',     s.expires_at,
    'server_time',    now(),
    'session_epoch',  coalesce(s.session_epoch, 0),
    'trial',          jsonb_build_object('enabled', v_trial_en, 'days', v_trial_days),
    'device_allowed', v_dev_allow,
    'device_block',   v_dev_block,
    'device_enforced', v_dev_enf,
    'device_count',   v_dev_count,
    'max_devices',    v_max_dev,
    'storage',        jsonb_build_object(
                        'used_bytes',  v_used,
                        'quota_bytes', v_quota,
                        'file_count',  v_files
                     )
  );
end;
$function$;
revoke all on function public.verify_license(jsonb) from public, anon;
grant execute on function public.verify_license(jsonb) to authenticated;
