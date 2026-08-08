-- ============================================================================
-- 0050 — دوال قراءة تكميلية لشاشة إدارة المستخدمين (المرحلة ٢ من اللوحة)
-- ============================================================================
--
--  النظام المعتمد يعطي **عدّادات** (device_count، counts) لكن شاشة الإدارة
--  تحتاج **قوائم**: أجهزة المستخدم بأعيانها (لإبطال جهازٍ محدد)، والخطط
--  (لمنتقي تغيير الخطة)، وسجلَّي العمليات (الإدارية على المستخدم، ونشاطه
--  التشغيلي). أربع دوال قراءةٍ فقط بنفس عقيدة النظام المعتمد حرفياً:
--  SECURITY DEFINER + search_path فارغ + _admin_guard أول سطر.
--
--  خصوصية سجلّ النشاط: audit_log التشغيلي يحمل في entity_id وdetail
--  معرّفاتٍ قد تتضمن أسماء مرضى (هوية p:هاتف:اسم) — الدالة تعيد
--  action/entity/at/device فقط، **لا** entity_id ولا detail. أرقام
--  المرضى لا تغادر عيادة صاحبها حتى نحو مالك المنصة.

-- ── ١) أجهزة مستخدم بأعيانها ────────────────────────────────────────────────
create or replace function public.admin_user_devices(p_user uuid)
returns jsonb
language plpgsql
stable
security definer
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
        'app_version', d.app_version,
        'first_seen',  d.first_seen,
        'last_seen',   d.last_seen,
        'revoked',     d.revoked
      ) order by d.last_seen desc)
    from public.devices d
    where d.user_id = p_user
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_user_devices(uuid) from public, anon;
grant execute on function public.admin_user_devices(uuid) to authenticated;

-- ── ٢) الخطط الفعالة (لمنتقي تغيير الخطة — admin_set_plan تقبل code) ───────
create or replace function public.admin_list_plans()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'code',        p.code,
        'name',        p.name,
        'description', p.description,
        'features',    p.features,
        'is_active',   p.is_active
      ) order by p.sort)
    from public.plans p
    where p.is_active
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_list_plans() from public, anon;
grant execute on function public.admin_list_plans() to authenticated;

-- ── ٣) سجل العمليات الإدارية على مستخدمٍ بعينه ─────────────────────────────
create or replace function public.admin_user_audit(
  p_user uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'at',          a.created_at,
        'actor_email', a.actor_email,
        'action',      a.action,
        'detail',      a.detail
      ) order by a.created_at desc)
    from (
      select * from public.admin_audit
      where target_user = p_user
      order by created_at desc
      limit v_limit
    ) a
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_user_audit(uuid, integer) from public, anon;
grant execute on function public.admin_user_audit(uuid, integer) to authenticated;

-- ── ٤) نشاط المستخدم التشغيلي (بلا أي محتوى مرضى — انظر رأس الملف) ─────────
create or replace function public.admin_user_activity(
  p_user uuid,
  p_limit integer default 50
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
  v_limit int  := least(greatest(coalesce(p_limit, 50), 1), 200);
begin
  return coalesce((
    select jsonb_agg(jsonb_build_object(
        'at',        l.at,
        'action',    l.action,
        'entity',    l.entity,
        'device_id', l.device_id
      ) order by l.at desc)
    from (
      select * from public.audit_log
      where user_id = p_user
      order by at desc
      limit v_limit
    ) l
  ), '[]'::jsonb);
end;
$$;

revoke all on function public.admin_user_activity(uuid, integer) from public, anon;
grant execute on function public.admin_user_activity(uuid, integer) to authenticated;
