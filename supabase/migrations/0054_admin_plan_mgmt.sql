-- 0054 — إدارة الخطط من اللوحة (المرحلة ٧): صفحة كاملة بعدّادات الاستخدام،
-- إنشاء/تعديل، نسخ، وحذف آمن. المزايا كلها مفاتيح JSON داخل features —
-- إضافة ميزة جديدة لا تتطلب أي تعديل كود، فقط مفتاحاً جديداً هنا.
--
-- العقيدة الأمنية: SECURITY DEFINER بمسار بحث فارغ + حارس _admin_guard داخل
-- كل دالة + تدقيق admin_audit لكل كتابة. لا صلاحية لغير authenticated.
--
-- حمايات خاصة:
--  • خطة «trial» محمية: لا حذف ولا تغيير رمزها (تعيين التجريبية يعتمد عليه).
--  • الحذف مرفوض ما دام على الخطة مشتركون أو أكواد (حتى المستهلكة — أثرٌ
--    تدقيقي) — عطّلها بدلاً من ذلك (is_active=false تخفيها عن الاختيار).

-- ١) صفحة الخطط الكاملة — النشطة والمعطلة معاً، بعدّادات الاستخدام.
--    (تكمّل admin_list_plans التي تُبقي على النشطة فقط لقوائم الاختيار.)
create or replace function public.admin_plans_page()
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
        'id',                 p.id,
        'code',               p.code,
        'name',               p.name,
        'description',        p.description,
        'features',           p.features,
        'is_active',          p.is_active,
        'sort',               p.sort,
        'subscribers',        coalesce(s.cnt, 0),
        'active_subscribers', coalesce(s.active_cnt, 0),
        'codes',              coalesce(c.cnt, 0),
        'unused_codes',       coalesce(c.unused_cnt, 0),
        'updated_at',         p.updated_at
      ) order by p.sort, p.created_at)
    from public.plans p
    left join lateral (
      select count(*) as cnt,
             count(*) filter (where sub.status in ('trial','active')) as active_cnt
        from public.subscriptions sub
       where sub.plan_id = p.id
    ) s on true
    left join lateral (
      select count(*) as cnt,
             count(*) filter (where ac.status = 'unused') as unused_cnt
        from public.activation_codes ac
       where ac.plan_id = p.id
    ) c on true
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_plans_page() from public, anon;
grant execute on function public.admin_plans_page() to authenticated;

-- ٢) إنشاء/تعديل خطة — p_id فارغ يعني إنشاء. يعيد صف الخطة بعد الحفظ.
--    رموز الأخطاء المتفق عليها مع اللوحة (تُترجم هناك):
--    plan_bad_code · plan_bad_name · plan_bad_features · plan_bad_limit ·
--    plan_not_found · plan_code_exists · plan_protected
create or replace function public.admin_upsert_plan(
  p_id          uuid,
  p_code        text,
  p_name        text,
  p_description text    default '',
  p_features    jsonb   default '{}'::jsonb,
  p_is_active   boolean default true,
  p_sort        integer default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor  uuid := (select auth.uid());
  v_email  text := public._admin_guard();
  v_code   text := lower(trim(coalesce(p_code, '')));
  v_name   text := trim(coalesce(p_name, ''));
  v_before jsonb;
  v_row    public.plans;
begin
  if v_code !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'plan_bad_code' using errcode = 'P0001';
  end if;
  if v_name = '' or length(v_name) > 60 then
    raise exception 'plan_bad_name' using errcode = 'P0001';
  end if;
  if p_features is null or jsonb_typeof(p_features) <> 'object' then
    raise exception 'plan_bad_features' using errcode = 'P0001';
  end if;
  -- الحدود الرقمية المعروفة إن وُجدت فأرقام غير سالبة (CASE يضمن ترتيب الفحص).
  perform 1
     from jsonb_each(p_features) as e(k, v)
    where e.k in ('storage_mb', 'max_clinics', 'max_devices')
      and (case when jsonb_typeof(e.v) <> 'number' then true
                else (e.v)::numeric < 0 end);
  if found then
    raise exception 'plan_bad_limit' using errcode = 'P0001';
  end if;

  if p_id is null then
    insert into public.plans (code, name, description, features, is_active, sort)
    values (
      v_code, v_name, left(coalesce(p_description, ''), 200), p_features,
      coalesce(p_is_active, true),
      coalesce(p_sort, (select coalesce(max(sort), -1) + 1 from public.plans))
    )
    returning * into v_row;
  else
    select to_jsonb(p) into v_before from public.plans p where p.id = p_id;
    if v_before is null then
      raise exception 'plan_not_found' using errcode = 'P0001';
    end if;
    -- «trial» عمود فقري لتعيين التجريبية — رمزها ثابت.
    if (v_before->>'code') = 'trial' and v_code <> 'trial' then
      raise exception 'plan_protected' using errcode = 'P0001';
    end if;
    update public.plans
       set code        = v_code,
           name        = v_name,
           description = left(coalesce(p_description, ''), 200),
           features    = p_features,
           is_active   = coalesce(p_is_active, true),
           sort        = coalesce(p_sort, sort),
           updated_at  = now()
     where id = p_id
    returning * into v_row;
  end if;

  insert into public.admin_audit (actor, actor_email, action, detail)
  values (v_actor, v_email,
          case when p_id is null then 'plan_create' else 'plan_update' end,
          jsonb_build_object('plan_id', v_row.id, 'code', v_row.code,
                             'before', v_before, 'after', to_jsonb(v_row)));
  return to_jsonb(v_row);
exception
  when unique_violation then
    raise exception 'plan_code_exists' using errcode = 'P0001';
end;
$$;

revoke all on function
  public.admin_upsert_plan(uuid, text, text, text, jsonb, boolean, integer)
  from public, anon;
grant execute on function
  public.admin_upsert_plan(uuid, text, text, text, jsonb, boolean, integer)
  to authenticated;

-- ٣) نسخ خطة — النسخة تبدأ معطَّلة (تُراجع ثم تُفعَّل) وتذهب لآخر الترتيب.
--    رمز صريح مكرر ⇒ خطأ؛ رمز مولَّد تلقائياً ⇒ لاحقة رقمية حتى يتفرّد.
create or replace function public.admin_copy_plan(
  p_id   uuid,
  p_code text default null,
  p_name text default null
) returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_email text := public._admin_guard();
  v_src   public.plans;
  v_base  text;
  v_code  text;
  v_row   public.plans;
  i       integer := 2;
begin
  select * into v_src from public.plans where id = p_id;
  if v_src.id is null then
    raise exception 'plan_not_found' using errcode = 'P0001';
  end if;

  v_base := lower(trim(coalesce(p_code, left(v_src.code, 27) || '_copy')));
  if v_base !~ '^[a-z0-9_]{2,32}$' then
    raise exception 'plan_bad_code' using errcode = 'P0001';
  end if;
  v_code := v_base;

  if p_code is not null then
    -- اختيار صريح: التصادم خطأ يعود للمشرف.
    if exists (select 1 from public.plans where code = v_code) then
      raise exception 'plan_code_exists' using errcode = 'P0001';
    end if;
  else
    -- توليد تلقائي: لاحقة تصاعدية حتى التفرد.
    while exists (select 1 from public.plans where code = v_code) loop
      v_code := left(v_base, 28) || '_' || i::text;
      i := i + 1;
      if i > 99 then
        raise exception 'plan_code_exists' using errcode = 'P0001';
      end if;
    end loop;
  end if;

  insert into public.plans (code, name, description, features, is_active, sort)
  values (
    v_code,
    coalesce(nullif(trim(coalesce(p_name, '')), ''), v_src.name || ' (نسخة)'),
    v_src.description, v_src.features, false,
    (select coalesce(max(sort), -1) + 1 from public.plans)
  )
  returning * into v_row;

  insert into public.admin_audit (actor, actor_email, action, detail)
  values (v_actor, v_email, 'plan_copy',
          jsonb_build_object('src_id', v_src.id, 'src_code', v_src.code,
                             'new_id', v_row.id, 'new_code', v_row.code));
  return to_jsonb(v_row);
end;
$$;

revoke all on function public.admin_copy_plan(uuid, text, text) from public, anon;
grant execute on function public.admin_copy_plan(uuid, text, text) to authenticated;

-- ٤) حذف آمن — يرفض المحمية والمستخدَمة، ويوثّق لقطة الصف المحذوف.
create or replace function public.admin_delete_plan(p_id uuid)
returns void
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor uuid := (select auth.uid());
  v_email text := public._admin_guard();
  v_row   public.plans;
  v_subs  bigint;
  v_codes bigint;
begin
  select * into v_row from public.plans where id = p_id;
  if v_row.id is null then
    raise exception 'plan_not_found' using errcode = 'P0001';
  end if;
  if v_row.code = 'trial' then
    raise exception 'plan_protected' using errcode = 'P0001';
  end if;

  select count(*) into v_subs  from public.subscriptions    where plan_id = p_id;
  select count(*) into v_codes from public.activation_codes where plan_id = p_id;
  if v_subs > 0 or v_codes > 0 then
    raise exception 'plan_in_use subs=% codes=%', v_subs, v_codes
      using errcode = 'P0001';
  end if;

  delete from public.plans where id = p_id;

  insert into public.admin_audit (actor, actor_email, action, detail)
  values (v_actor, v_email, 'plan_delete',
          jsonb_build_object('plan', to_jsonb(v_row)));
end;
$$;

revoke all on function public.admin_delete_plan(uuid) from public, anon;
grant execute on function public.admin_delete_plan(uuid) to authenticated;
