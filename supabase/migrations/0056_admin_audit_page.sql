-- 0056 — صفحة سجل العمليات الشامل (المرحلة ٩): قراءة مرشَّحة ومرقَّمة
-- لجدول admin_audit الذي تملؤه كل عمليات المشرفين أصلاً منذ المراحل السابقة.
--
-- بحت للقراءة (لا كتابة) — الحارس يمنع غير المشرفين. يُثري البريد الهدف من
-- auth.users حين تركته دالة قديمة فارغاً (مثل admin_set_plan الأولى).

create or replace function public.admin_audit_page(
  p_action text    default null,
  p_search text    default null,
  p_limit  integer default 50,
  p_offset integer default 0
) returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_email  text := public._admin_guard();
  v_lim    integer := least(greatest(coalesce(p_limit, 50), 1), 200);
  v_off    integer := greatest(coalesce(p_offset, 0), 0);
  v_action text := nullif(trim(coalesce(p_action, '')), '');
  v_q      text := nullif(trim(coalesce(p_search, '')), '');
  v_total  bigint;
  v_rows   jsonb;
begin
  -- CTE واحد: فلترة ثم تعداد ثم صفحة — إثراء البريد الهدف بالانضمام الكسول.
  with filtered as (
    select a.id, a.actor_email, a.action, a.created_at, a.detail,
           a.target_user,
           coalesce(a.target_email, tu.email) as target_email
      from public.admin_audit a
      left join auth.users tu on tu.id = a.target_user
     where (v_action is null or a.action = v_action)
       and (v_q is null
            or a.actor_email ilike '%' || v_q || '%'
            or coalesce(a.target_email, tu.email) ilike '%' || v_q || '%')
  )
  select count(*) into v_total from filtered;

  with filtered as (
    select a.id, a.actor_email, a.action, a.created_at, a.detail,
           a.target_user,
           coalesce(a.target_email, tu.email) as target_email
      from public.admin_audit a
      left join auth.users tu on tu.id = a.target_user
     where (v_action is null or a.action = v_action)
       and (v_q is null
            or a.actor_email ilike '%' || v_q || '%'
            or coalesce(a.target_email, tu.email) ilike '%' || v_q || '%')
  )
  select coalesce(jsonb_agg(jsonb_build_object(
           'id',           f.id,
           'at',           f.created_at,
           'actor_email',  f.actor_email,
           'action',       f.action,
           'target_email', f.target_email,
           'detail',       f.detail
         ) order by f.id desc), '[]'::jsonb)
    into v_rows
    from (select * from filtered order by id desc
           limit v_lim offset v_off) f;

  return jsonb_build_object(
    'total',  v_total,
    'limit',  v_lim,
    'offset', v_off,
    'rows',   v_rows
  );
end;
$$;

revoke all on function public.admin_audit_page(text, text, integer, integer)
  from public, anon;
grant execute on function public.admin_audit_page(text, text, integer, integer)
  to authenticated;

-- فهرس خفيف يسند الترتيب التنازلي والفلترة بالفعل (السجل ينمو بلا حدّ).
create index if not exists admin_audit_action_id_idx
  on public.admin_audit (action, id desc);
