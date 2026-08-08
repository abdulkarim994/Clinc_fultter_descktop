-- ============================================================================
--  0027 — دالة دفع قيود التدقيق
--  ⚠ مُطبَّقة على الإنتاج: 2026-07-31
-- ============================================================================
--
--  SECURITY INVOKER عمداً (لا DEFINER): تبقى سياسة RLS هي الحاكم، فلا تفتح
--  الدالة باباً جانبياً حول السياسة التي وُضعت لتوّها. وهذا يخالف بقية دوال
--  المزامنة عمداً — تلك تحتاج تجاوزاً مدروساً، وسجلّ التدقيق لا يحتاج إلا
--  أقلّ صلاحية ممكنة.
--
--  `on conflict do nothing` يجعل الدفع عديم الأثر: انقطاع شبكة بين الإدراج
--  والإقرار يجعل العميل يعيد الإرسال، ولا يجوز أن تتكرّر القيود — سجلٌّ فيه
--  الحدث مرتين يُفقد الثقة بالعدد.
--
--  يُرجع عدد المُدرَج فعلاً لا عدد المُرسَل — ليُميّز العميل الجديد من
--  المكرّر عند التشخيص.

create or replace function public.push_audit(p_events jsonb)
returns int
language plpgsql
security invoker
set search_path to 'public', 'extensions', 'pg_temp'
as $$
declare
  v_uid uuid := auth.uid();
  v_inserted int;
begin
  if v_uid is null then
    raise exception 'غير مصادَق';
  end if;
  if p_events is null or jsonb_typeof(p_events) <> 'array' then
    return 0;
  end if;
  if jsonb_array_length(p_events) > 1000 then
    raise exception 'دفعة أكبر من المسموح (1000)';
  end if;

  with ins as (
    insert into public.audit_log
      (id, user_id, at, actor_uid, device_id, action, entity, entity_id, detail)
    select
      e->>'id',
      v_uid,
      to_timestamp((e->>'at')::bigint / 1000.0),
      e->>'actor_uid',
      e->>'device_id',
      e->>'action',
      nullif(e->>'entity', ''),
      nullif(e->>'entity_id', ''),
      case when jsonb_typeof(e->'detail') = 'object' then e->'detail' else null end
    from jsonb_array_elements(p_events) as e
    where e->>'id' is not null and e->>'action' is not null
      and e->>'at' ~ '^[0-9]+$'
    on conflict (id) do nothing
    returning 1
  )
  select count(*) into v_inserted from ins;

  return v_inserted;
end;
$$;

comment on function public.push_audit(jsonb) is
  'م79 — دفع قيود تدقيق عديم الأثر. SECURITY INVOKER — RLS هو الحاكم.';

revoke all on function public.push_audit(jsonb) from public, anon;
grant execute on function public.push_audit(jsonb) to authenticated;
