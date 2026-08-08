-- 0055 — التجديد والترقية الذرّيان (المرحلة ٨): عملية واحدة تجمع
-- التجديد/التمديد/تغيير الخطة بدل ثلاث نداءات منفصلة غير ذرّية.
--
-- الدلالة:
--  • p_days > 0: يمدَّد الانتهاء من max(الآن، الانتهاء الحالي) — أي أن
--    المتبقي لا يضيع عند التجديد المبكر؛ وp_from_now=true يجدد من اليوم
--    متجاهلاً المتبقي (سياسة صريحة بيد المشرف).
--  • p_plan (اختياري): تغيير الخطة في العملية نفسها — النشطة فقط.
--  • p_days = 0 مع p_plan: تغيير خطة فقط دون مساس بالانتهاء.
--  • الحالة تصير active دائماً (تجديد منتهٍ/تجريبي = تفعيل) — لكن المحظور
--    والمجمَّد يُرفضان صراحةً: قرارا الحظر/التجميد لا يُلغيان ضمنياً بتجديد،
--    بل بفكّهما المتعمَّد من قسم الحالة أولاً.
--
-- رموز الأخطاء (تُترجم في اللوحة): renew_bad_days · renew_nothing ·
-- renew_user_not_found · renew_banned · renew_frozen · plan_not_found ·
-- plan_inactive

create or replace function public.admin_renew_subscription(
  p_user     uuid,
  p_days     integer,
  p_plan     text    default null,
  p_from_now boolean default false
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor        uuid := (select auth.uid());
  v_email        text := public._admin_guard();
  v_target_email text;
  v_sub          public.subscriptions;
  v_plan         public.plans;
  v_base         timestamptz;
  v_new_expiry   timestamptz;
  v_before       jsonb;
begin
  if p_days is null or p_days < 0 or p_days > 3650 then
    raise exception 'renew_bad_days' using errcode = 'P0001';
  end if;
  if p_days = 0 and p_plan is null then
    raise exception 'renew_nothing' using errcode = 'P0001';
  end if;

  select email into v_target_email from auth.users where id = p_user;
  if v_target_email is null then
    raise exception 'renew_user_not_found' using errcode = 'P0001';
  end if;

  if p_plan is not null then
    select * into v_plan from public.plans where code = p_plan;
    if v_plan.id is null then
      raise exception 'plan_not_found' using errcode = 'P0001';
    end if;
    if not v_plan.is_active then
      raise exception 'plan_inactive' using errcode = 'P0001';
    end if;
  end if;

  select * into v_sub from public.subscriptions where user_id = p_user;
  v_before := to_jsonb(v_sub);

  if v_sub.status = 'banned' then
    raise exception 'renew_banned' using errcode = 'P0001';
  end if;
  if v_sub.status = 'frozen' then
    raise exception 'renew_frozen' using errcode = 'P0001';
  end if;

  if p_days > 0 then
    v_base := case
      when p_from_now
        or v_sub.expires_at is null
        or v_sub.expires_at < now()
      then now()
      else v_sub.expires_at
    end;
    v_new_expiry := v_base + make_interval(days => p_days);
  else
    v_new_expiry := v_sub.expires_at; -- تغيير خطة فقط
  end if;

  insert into public.subscriptions
    (user_id, plan_id, status, starts_at, expires_at, trial, updated_at)
  values
    (p_user, v_plan.id, 'active', now(), v_new_expiry, false, now())
  on conflict (user_id) do update
    set plan_id    = coalesce(v_plan.id, public.subscriptions.plan_id),
        status     = 'active',
        starts_at  = coalesce(public.subscriptions.starts_at, now()),
        expires_at = excluded.expires_at,
        trial      = false,
        updated_at = now();

  select * into v_sub from public.subscriptions where user_id = p_user;

  insert into public.admin_audit
    (actor, actor_email, action, target_user, target_email, detail)
  values
    (v_actor, v_email, 'renew', p_user, v_target_email,
     jsonb_build_object('days', p_days, 'plan', p_plan,
                        'from_now', p_from_now,
                        'before', v_before, 'after', to_jsonb(v_sub)));

  return jsonb_build_object(
    'status',     v_sub.status,
    'plan_code',  (select code from public.plans where id = v_sub.plan_id),
    'expires_at', v_sub.expires_at
  );
end;
$$;

revoke all on function
  public.admin_renew_subscription(uuid, integer, text, boolean)
  from public, anon;
grant execute on function
  public.admin_renew_subscription(uuid, integer, text, boolean)
  to authenticated;
