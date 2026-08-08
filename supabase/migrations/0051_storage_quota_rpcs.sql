-- ============================================================================
-- 0051 — حلقة التخزين: قياس الجهاز → إبلاغ الخادم → رؤية اللوحة (المرحلة ٣)
-- ============================================================================
--
--  الحقيقة المكتشَفة: أحجام صور الأشعة تعيش في Cloudflare R2 (بادئة كل
--  مستخدم = user_id)، لا في Postgres، وجدول storage_usage فارغ. فمصدر
--  القياس الأصدق هو **الجهاز نفسه**: تطبيق العيادة يعرف بايتات كل صورة
--  خزّنها. لذا:
--    • get_my_storage      — يقرأ المستخدم حصته واستهلاكه المبلَّغ.
--    • report_my_storage   — الجهاز يبلّغ قياسه (self فقط) فيراه المالك.
--    • storage_usage_daily — لقطة يومية لكل مستخدم ⇒ نمو وتوقّع الامتلاء.
--    • admin_storage_page  — قائمة اللوحة بالحصص والاستهلاك والنمو.
--
--  الحصة تُشتقّ بترتيب: تجاوز storage_usage.quota_bytes الفردي (يضبطه
--  admin_set_storage_quota القائم) ← وإلا storage_mb من الميزات الفعالة
--  ← وإلا 200 م.ب أرضية. كلها بعقيدة النظام: SECURITY DEFINER +
--  search_path فارغ + العزل بـauth.uid() داخل الدالة.

-- ── ١) تاريخ الاستهلاك اليومي (للنمو والتوقع) ──────────────────────────────
create table if not exists public.storage_usage_daily (
  user_id    uuid not null references auth.users(id) on delete cascade,
  day        date not null,
  used_bytes bigint not null default 0,
  file_count integer not null default 0,
  primary key (user_id, day)
);
alter table public.storage_usage_daily enable row level security;
revoke all on table public.storage_usage_daily from anon, authenticated;

-- ── ٢) اشتقاق حصة مستخدم بالبايت (دالة مساعدة داخلية) ──────────────────────
create or replace function public.storage_quota_bytes(p_user uuid)
returns bigint
language sql
stable
security definer
set search_path to ''
as $$
  select coalesce(
    (select su.quota_bytes from public.storage_usage su
       where su.user_id = p_user and su.quota_bytes is not null),
    (select ((public.effective_features(p_user)->>'storage_mb')::bigint) * 1048576
       where (public.effective_features(p_user)->>'storage_mb') is not null),
    200 * 1048576
  );
$$;
revoke all on function public.storage_quota_bytes(uuid) from public, anon;
grant execute on function public.storage_quota_bytes(uuid) to authenticated;

-- ── ٣) قراءة المستخدم لحصته (self) ─────────────────────────────────────────
create or replace function public.get_my_storage()
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_used bigint;
  v_files int;
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;
  select coalesce(used_bytes, 0), coalesce(file_count, 0)
    into v_used, v_files
    from public.storage_usage where user_id = v_uid;
  return jsonb_build_object(
    'used_bytes',  coalesce(v_used, 0),
    'file_count',  coalesce(v_files, 0),
    'quota_bytes', public.storage_quota_bytes(v_uid)
  );
end;
$$;
revoke all on function public.get_my_storage() from public, anon;
grant execute on function public.get_my_storage() to authenticated;

-- ── ٤) إبلاغ الجهاز عن قياسه (self — لا يمسّ الحصة ولا مستخدماً آخر) ───────
create or replace function public.report_my_storage(
  p_used_bytes bigint,
  p_file_count integer
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $$
declare
  v_uid uuid := (select auth.uid());
  v_used bigint := greatest(coalesce(p_used_bytes, 0), 0);
  v_files int  := greatest(coalesce(p_file_count, 0), 0);
begin
  if v_uid is null then
    raise exception 'not authenticated' using errcode = '28000';
  end if;

  -- الحالة الحيّة (quota_bytes لا يُمسّ — قرار إداري وحده).
  insert into public.storage_usage (user_id, used_bytes, file_count, updated_at)
  values (v_uid, v_used, v_files, now())
  on conflict (user_id) do update
    set used_bytes = excluded.used_bytes,
        file_count = excluded.file_count,
        updated_at = now();

  -- لقطة اليوم (أحدث قياس لليوم يفوز) — أساس النمو والتوقّع.
  insert into public.storage_usage_daily (user_id, day, used_bytes, file_count)
  values (v_uid, current_date, v_used, v_files)
  on conflict (user_id, day) do update
    set used_bytes = excluded.used_bytes,
        file_count = excluded.file_count;

  return public.get_my_storage();
end;
$$;
revoke all on function public.report_my_storage(bigint, integer) from public, anon;
grant execute on function public.report_my_storage(bigint, integer) to authenticated;

-- ── ٥) قائمة اللوحة: حصص واستهلاك ونمو لكل مستخدم (admin) ──────────────────
--  النمو: فرق آخر قياس عن أقدم قياسٍ ضمن نافذة، مقسوماً على أيامها ⇒ معدل
--  يومي، ومنه توقّع الأيام حتى الامتلاء. كله من storage_usage_daily.
create or replace function public.admin_storage_page(
  p_limit integer default 200,
  p_offset integer default 0
)
returns jsonb
language plpgsql
stable
security definer
set search_path to ''
as $$
declare
  v_email text := public._admin_guard();
  v_limit int  := least(greatest(coalesce(p_limit, 200), 1), 500);
  v_offset int := greatest(coalesce(p_offset, 0), 0);
  v_rows jsonb;
begin
  select coalesce(jsonb_agg(row_to_json(t)), '[]'::jsonb) into v_rows
  from (
    select
      pr.id    as user_id,
      pr.email,
      pr.full_name,
      public.storage_quota_bytes(pr.id) as quota_bytes,
      coalesce(su.used_bytes, 0)        as used_bytes,
      coalesce(su.file_count, 0)        as file_count,
      su.updated_at                     as measured_at,
      pl.code                           as plan_code,
      -- معدل النمو اليومي من نافذة ٣٠ يوماً (بايت/يوم) + توقّع الامتلاء.
      gr.daily_rate,
      gr.days_to_full,
      gr.history
    from public.profiles pr
    left join public.storage_usage su on su.user_id = pr.id
    left join public.subscriptions s  on s.user_id  = pr.id
    left join public.plans pl         on pl.id      = s.plan_id
    left join lateral (
      select
        case when max(d.day) > min(d.day)
             then greatest(
               (max(d.used_bytes) filter (where d.day = mx.mxday)
                - min(d.used_bytes) filter (where d.day = mn.mnday))
               / nullif((mx.mxday - mn.mnday), 0), 0)
             else 0 end as daily_rate,
        case when max(d.day) > min(d.day)
             and (max(d.used_bytes) filter (where d.day = mx.mxday)
                  - min(d.used_bytes) filter (where d.day = mn.mnday)) > 0
             then floor(
               (public.storage_quota_bytes(pr.id)
                 - max(d.used_bytes) filter (where d.day = mx.mxday))
               / nullif(((max(d.used_bytes) filter (where d.day = mx.mxday)
                  - min(d.used_bytes) filter (where d.day = mn.mnday))
                  / nullif((mx.mxday - mn.mnday), 0)), 0))
             else null end as days_to_full,
        (select jsonb_agg(jsonb_build_object('day', dd.day, 'used', dd.used_bytes)
                  order by dd.day)
           from public.storage_usage_daily dd
          where dd.user_id = pr.id
            and dd.day >= current_date - 30) as history
      from public.storage_usage_daily d
      cross join lateral (select max(day) mxday, min(day) mnday
                            from public.storage_usage_daily
                           where user_id = pr.id
                             and day >= current_date - 30) g
      cross join lateral (select g.mxday) mx
      cross join lateral (select g.mnday) mn
      where d.user_id = pr.id and d.day >= current_date - 30
      group by mx.mxday, mn.mnday
    ) gr on true
    order by coalesce(su.used_bytes, 0) desc, pr.created_at asc
    limit v_limit offset v_offset
  ) t;

  return jsonb_build_object(
    'total', (select count(*) from public.profiles),
    'rows',  v_rows
  );
end;
$$;
revoke all on function public.admin_storage_page(integer, integer) from public, anon;
grant execute on function public.admin_storage_page(integer, integer) to authenticated;
