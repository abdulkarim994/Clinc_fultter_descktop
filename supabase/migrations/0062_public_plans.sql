-- 0062 — قائمة الباقات العامة (المرحلة د). قراءةٌ بحتة يستعملها المستخدم
-- العادي في شاشة الاشتراك لمقارنة باقته بالأعلى (لا كشف لأي بيانات حساسة —
-- الباقات النشطة فقط: الرمز والاسم والمزايا والترتيب). لا صلة بأي إنفاذ.

create or replace function public.list_public_plans()
returns jsonb
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(jsonb_agg(jsonb_build_object(
      'code',     p.code,
      'name',     p.name,
      'features', p.features,
      'sort',     p.sort
    ) order by p.sort), '[]'::jsonb)
  from public.plans p
  where p.is_active;
$$;

revoke all on function public.list_public_plans() from public, anon;
grant execute on function public.list_public_plans() to authenticated;
