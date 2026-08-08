-- ============================================================================
-- 0052 — إدارة أكواد التفعيل: القائمة والإبطال (المرحلة ٤ من اللوحة)
-- ============================================================================
--
--  النظام المعتمد يولّد الأكواد (admin_generate_codes: نصٌّ يظهر مرةً
--  واحدة، وتجزئة SHA-256 هي المخزَّنة) ويستهلكها (activate_code)، لكنه بلا
--  **قائمةٍ** تُدار منها ولا **إبطالٍ** لكودٍ خرج عن السيطرة. دالتا قراءة
--  وكتابة بنفس العقيدة: SECURITY DEFINER + search_path فارغ + _admin_guard.
--
--  الإبطال لغير المستخدَم فقط: الكود المستخدَم منح اشتراكه بالفعل —
--  والتعامل مع صاحبه يكون بدوال المستخدم (تجميد/إعادة تعيين) لا بالكود.

-- ── ١) قائمة الأكواد (مرشَّحة بالحالة اختيارياً) ────────────────────────────
create or replace function public.admin_codes_page(
  p_limit integer default 100,
  p_offset integer default 0,
  p_status text default null
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
  v_limit int  := least(greatest(coalesce(p_limit, 100), 1), 500);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb;
  v_total int;
begin
  if p_status is not null
     and p_status not in ('unused','used','revoked') then
    raise exception 'unknown status filter: %', p_status using errcode = 'P0001';
  end if;

  select count(*) into v_total
    from public.activation_codes c
   where p_status is null or c.status = p_status;

  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows
  from (
    select
      c.id,
      c.code_prefix,
      c.status,
      pl.code            as plan_code,
      c.duration_days,
      c.starts_at,
      c.expires_at,
      c.features,
      c.bound_email,
      c.used_at,
      c.note,
      c.created_at
    from public.activation_codes c
    left join public.plans pl on pl.id = c.plan_id
    where p_status is null or c.status = p_status
    order by c.created_at desc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object(
    'total',  v_total,
    'limit',  v_limit,
    'offset', v_offset,
    'rows',   v_rows
  );
end;
$$;

revoke all on function public.admin_codes_page(integer, integer, text)
  from public, anon;
grant execute on function public.admin_codes_page(integer, integer, text)
  to authenticated;

-- ── ٢) إبطال كود غير مستخدَم ────────────────────────────────────────────────
create or replace function public.admin_revoke_code(p_code_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_actor  uuid := (select auth.uid());
  v_email  text := public._admin_guard();
  v_status text;
  v_prefix text;
begin
  select status, code_prefix into v_status, v_prefix
    from public.activation_codes where id = p_code_id
    for update;

  if v_status is null then
    raise exception 'code not found' using errcode = 'P0001';
  end if;
  if v_status = 'used' then
    raise exception 'code already used — manage the user instead'
      using errcode = 'P0001';
  end if;
  if v_status = 'revoked' then
    return jsonb_build_object('ok', true, 'already', true);
  end if;

  update public.activation_codes
     set status = 'revoked', updated_at = now()
   where id = p_code_id;

  insert into public.admin_audit (actor, actor_email, action, detail)
  values (v_actor, v_email, 'code_revoked',
          jsonb_build_object('code_id', p_code_id, 'prefix', v_prefix));

  return jsonb_build_object('ok', true);
end;
$$;

revoke all on function public.admin_revoke_code(uuid) from public, anon;
grant execute on function public.admin_revoke_code(uuid) to authenticated;
