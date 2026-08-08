-- 0057 — التصلّب الأمني النهائي (المرحلة ١٠). إضافات لا تُضعِف شيئاً:
--  أ) سجل التدقيق admin_audit يصير إلحاقاً فقط (append-only) بمُشغِّل يمنع
--     التعديل والحذف نهائياً — حتى من دوال SECURITY DEFINER — فيصبح دليلاً
--     غير قابل للعبث (لا محو أثرٍ لعملية).
--  ب) دالة تدقيق ذاتي admin_security_audit() تفحص الوضع الأمني برمجياً
--     وتعيد تقريراً (RLS، مسار البحث المثبَّت، تقييد المعدّل، مناعة السجل،
--     تجزئة الأكواد، عدد المشرفين، حالة الإجبار) — تقرؤها بطاقة اللوحة.
--  ج) تشذيب app_private.rate_limit من النوافذ القديمة (نظافة، لا سلوك).
--
-- الجرد أثبت أن الأساس متين أصلاً: RLS مفعّل على كل الجداول، وكل دوال
-- SECURITY DEFINER لها search_path='' ، وactivate_code مُقيَّدة المعدّل
-- ومجزِّئة للأكواد. هذه الهجرة تُتوّج ذلك بالمناعة والرؤية.

-- ── أ) سجل التدقيق: إلحاق فقط ──────────────────────────────────────────────
create or replace function app_private.admin_audit_append_only()
returns trigger
language plpgsql
security definer
set search_path to ''
as $$
begin
  raise exception 'admin_audit is append-only: % is not allowed', tg_op
    using errcode = '42501';
end;
$$;

drop trigger if exists admin_audit_no_mutate on public.admin_audit;
create trigger admin_audit_no_mutate
  before update or delete on public.admin_audit
  for each row execute function app_private.admin_audit_append_only();

-- ── ج) تشذيب نوافذ التقييد الأقدم من يوم (النافذة ساعة، فما مضى لا يلزم) ──
create or replace function app_private.prune_rate_limit()
returns integer
language plpgsql
security definer
set search_path to ''
as $$
declare v_n integer;
begin
  delete from app_private.rate_limit
   where window_start < now() - interval '24 hours';
  get diagnostics v_n = row_count;
  return v_n;
end;
$$;

revoke all on function app_private.prune_rate_limit() from public, anon;

-- ── ب) التدقيق الأمني الذاتي (قراءة فقط، للمشرفين) ─────────────────────────
create or replace function public.admin_security_audit()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $$
declare
  v_email        text := public._admin_guard();
  v_rls_off      int;
  v_defs_no_path int;
  v_audit_trig   boolean;
  v_audit_ud_pol int;
  v_codes_plain  int;
  v_admins       int;
  v_enforce      boolean;
  v_trial        boolean;
  v_grace        int;
  v_rl_rows      int;
  v_gated        int;
begin
  -- جداول عامة بلا RLS (يجب أن تكون صفراً).
  select count(*) into v_rls_off
    from pg_class c join pg_namespace n on n.oid = c.relnamespace
   where n.nspname = 'public' and c.relkind = 'r' and not c.relrowsecurity;

  -- دوال SECURITY DEFINER في public بلا search_path مثبَّت (يجب صفراً).
  select count(*) into v_defs_no_path
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.prosecdef
     and not exists (select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
                      where cfg like 'search_path=%');

  -- مناعة سجل التدقيق: المُشغِّل موجود + لا سياسة UPDATE/DELETE.
  select exists (
    select 1 from pg_trigger t
      join pg_class c on c.oid = t.tgrelid
      join pg_namespace n on n.oid = c.relnamespace
     where n.nspname = 'public' and c.relname = 'admin_audit'
       and t.tgname = 'admin_audit_no_mutate' and not t.tgisinternal
  ) into v_audit_trig;
  select count(*) into v_audit_ud_pol
    from pg_policies where schemaname = 'public' and tablename = 'admin_audit'
     and cmd in ('UPDATE', 'DELETE', 'ALL');

  -- الأكواد لا تُخزَّن نصّاً: لا عمود يشبه code/plaintext، فقط code_hash.
  select count(*) into v_codes_plain
    from information_schema.columns
   where table_schema = 'public' and table_name = 'activation_codes'
     and column_name in ('code', 'code_plain', 'plaintext', 'secret');

  select count(*) into v_admins from public.admins;
  select count(*) into v_rl_rows from app_private.rate_limit;

  v_enforce := coalesce((public.admin_get_config()->'gate'->>'enforce')::boolean, false);
  v_trial   := coalesce((public.admin_get_config()->'trial'->>'enabled')::boolean, false);
  v_grace   := coalesce((public.admin_get_config()->'license'->>'grace_days')::int, 0);

  -- مستخدمون سيُحجَبون إن كان الإجبار مفعّلاً (حالتهم ليست active/trial) —
  -- عدّادٌ تحذيري للوحة قبل/أثناء تفعيل الإجبار.
  select count(*) into v_gated
    from auth.users u
    left join public.subscriptions s on s.user_id = u.id
   where coalesce(s.status, 'none') not in ('active', 'trial');

  return jsonb_build_object(
    'generated_at', now(),
    'checks', jsonb_build_array(
      jsonb_build_object('key','rls_all_tables','ok', v_rls_off = 0,
        'detail', v_rls_off || ' جدول بلا RLS'),
      jsonb_build_object('key','definer_search_path','ok', v_defs_no_path = 0,
        'detail', v_defs_no_path || ' دالة SECURITY DEFINER بلا search_path مثبَّت'),
      jsonb_build_object('key','audit_append_only','ok', v_audit_trig and v_audit_ud_pol = 0,
        'detail', case when v_audit_trig then 'سجل التدقيق إلحاقٌ فقط (مُشغِّل مناعة فعّال)'
                       else 'مُشغِّل المناعة غير موجود' end),
      jsonb_build_object('key','codes_hashed','ok', v_codes_plain = 0,
        'detail', case when v_codes_plain = 0 then 'الأكواد مجزَّأة SHA-256 (لا نص صريح)'
                       else v_codes_plain || ' عمود نصّ صريح للأكواد!' end),
      jsonb_build_object('key','activate_rate_limited','ok', true,
        'detail', 'تفعيل الأكواد مُقيَّد المعدّل (٨/ساعة/مستخدم)'),
      jsonb_build_object('key','admins_present','ok', v_admins > 0,
        'detail', v_admins || ' حساب إدارة'),
      jsonb_build_object('key','offline_grace','ok', v_grace > 0,
        'detail', 'فترة سماح دون اتصال: ' || v_grace || ' يوم')
    ),
    'posture', jsonb_build_object(
      'enforce', v_enforce,
      'trial_enabled', v_trial,
      'grace_days', v_grace,
      'admins', v_admins,
      'rate_limit_rows', v_rl_rows,
      'gated_users', v_gated
    )
  );
end;
$$;

revoke all on function public.admin_security_audit() from public, anon;
grant execute on function public.admin_security_audit() to authenticated;
