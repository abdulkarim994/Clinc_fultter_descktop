-- 0063 — توسعة التدقيق الأمني الذاتي (المرحلة و). امتدادٌ لا يُضعِف شيئاً:
--
--  المراحل أ/ب/ج (0058/0059/0060) أضافت ثلاثة حُرّاس على الخادم — التخزين
--  والعيادات والأجهزة — كلٌّ خلف مفتاحٍ فرعي مستقل في gate يبدأ **مطفأً**
--  (قياسٌ لمن سيتأثّر قبل قرار التفعيل، بينما gate.enforce العام مفعّل).
--  لكن دالة التدقيق الذاتي admin_security_audit() (من 0057) لا تعرف بهذه
--  المفاتيح الجديدة ولا بعدد من سيتأثّر بكلٍّ منها، فبطاقةُ اللوحة عمياء
--  عنها. هذه الهجرة **توسّع** الدالة (CREATE OR REPLACE) فتُبقي فحوصها
--  السبعة ومفاتيح posture الأصلية حرفياً، وتضيف فوقها:
--    • حالة المفاتيح الفرعية الثلاثة (enforce_storage/clinics/devices).
--    • عدّاد «من سيتأثّر» لكل ضابط لو فُعِّل: storage_over/clinics_over/
--      devices_over — يُحسب من نفس منطق الحُرّاس تماماً (حصة/حد فعّال > 0
--      وتجاوزٌ فعلي)، فيرى المالك حجم الأثر قبل أن يقلب أي مفتاح.
--    • فحصٌ جديد enforcement_subflags يلخّص أيّ المفاتيح مطفأ/مفعّل.
--
--  لا مساس بالسلوك: الدالة تبقى قراءة-فقط، STABLE، SECURITY DEFINER بمسار
--  بحثٍ فارغ، محروسةً بـ_admin_guard أول سطر — والقيم الأصلية تُحسب بنفس
--  المصادر (admin_get_config لـ enforce/trial/grace، وapp_private مباشرةً
--  عبر admin_get_config->'gate' للمفاتيح الفرعية، اتساقاً مع الحُرّاس).

create or replace function public.admin_security_audit()
returns jsonb
language plpgsql
stable security definer
set search_path to ''
as $function$
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
  -- المرحلة و — المفاتيح الفرعية وعدّادات الأثر.
  v_gate         jsonb;
  v_enf_storage  boolean;
  v_enf_clinics  boolean;
  v_enf_devices  boolean;
  v_storage_over int;
  v_clinics_over int;
  v_devices_over int;
  v_sub_detail   text;
begin
  -- ── الفحوص السبعة الأصلية (منسوخة حرفياً من 0057) ───────────────────────

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

  -- مناعة سجل التدقيق: المُشغِّل موجود + لا سياسة UPDATE/DELETE/ALL.
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
  v_grace   := coalesce((public.admin_get_config()->'license'->>'grace_days')::int, 7);

  -- مستخدمون سيُحجَبون إن كان الإجبار مفعّلاً (حالتهم ليست active/trial) —
  -- عدّادٌ تحذيري للوحة قبل/أثناء تفعيل الإجبار.
  select count(*) into v_gated
    from auth.users u
    left join public.subscriptions s on s.user_id = u.id
   where coalesce(s.status, 'none') not in ('active', 'trial');

  -- ── المرحلة و — المفاتيح الفرعية للإنفاذ (كائن gate مرّةً واحدة) ─────────
  v_gate        := public.admin_get_config()->'gate';
  v_enf_storage := coalesce((v_gate->>'enforce_storage')::boolean, false);
  v_enf_clinics := coalesce((v_gate->>'enforce_clinics')::boolean, false);
  v_enf_devices := coalesce((v_gate->>'enforce_devices')::boolean, false);

  -- من سيتأثّر لو فُعِّل حارس التخزين: استهلاكٌ يفوق حصةً موجبةً فعليّة —
  -- نفس منطق storage_can_upload (حصة > 0، وused > الحصة).
  select count(*) into v_storage_over
    from auth.users u
    left join public.storage_usage su on su.user_id = u.id
   where public.storage_quota_bytes(u.id) > 0
     and coalesce(su.used_bytes, 0) > public.storage_quota_bytes(u.id);

  -- من سيتأثّر لو فُعِّل حارس العيادات: عددُ العيادات في صفّ الإعدادات
  -- app.config يفوق max_clinics الفعّال الموجب — نفس منطق clinics_guard.
  select count(*) into v_clinics_over
    from auth.users u
   where nullif(public.effective_features(u.id)->>'max_clinics', '')::int is not null
     and nullif(public.effective_features(u.id)->>'max_clinics', '')::int > 0
     and coalesce((
           select jsonb_array_length(sr.payload->'value'->'clinics')
             from public.sync_rows sr
            where sr.user_id = u.id
              and sr.entity = 'settings'
              and sr.id = 'app.config'
              and jsonb_typeof(sr.payload->'value'->'clinics') = 'array'
         ), 0) > nullif(public.effective_features(u.id)->>'max_clinics', '')::int;

  -- من سيتأثّر لو فُعِّل حارس الأجهزة: أجهزةٌ غير مبطَلة تفوق max_devices
  -- الفعّال الموجب — نفس منطق verify_license (revoked=false، count > max).
  select count(*) into v_devices_over
    from auth.users u
   where nullif(public.effective_features(u.id)->>'max_devices', '')::int is not null
     and nullif(public.effective_features(u.id)->>'max_devices', '')::int > 0
     and (select count(*) from public.devices d
           where d.user_id = u.id and not d.revoked)
         > nullif(public.effective_features(u.id)->>'max_devices', '')::int;

  -- ملخّص نصّي لحالة المفاتيح الفرعية (يُعرض في تفصيل الفحص الجديد).
  v_sub_detail :=
       'التخزين: '  || case when v_enf_storage then 'مفعّل' else 'مطفأ' end
    || ' · العيادات: ' || case when v_enf_clinics then 'مفعّل' else 'مطفأ' end
    || ' · الأجهزة: '  || case when v_enf_devices then 'مفعّل' else 'مطفأ' end;

  return jsonb_build_object(
    'generated_at', now(),
    'checks', jsonb_build_array(
      jsonb_build_object('key','rls_all_tables','ok', v_rls_off = 0,
        'detail', v_rls_off || ' جدول بلا RLS'),
      jsonb_build_object('key','definer_search_path','ok', v_defs_no_path = 0,
        'detail', v_defs_no_path || ' دالة SECURITY DEFINER بلا search_path مثبَّت'),
      jsonb_build_object('key','audit_append_only','ok', v_audit_trig and v_audit_ud_pol = 0,
        'detail', case when v_audit_trig and v_audit_ud_pol = 0 then 'سجل التدقيق إلحاقٌ فقط'
                       when v_audit_trig then 'مُشغِّل المناعة فعّال لكن توجد سياسة تعديل/حذف'
                       else 'مُشغِّل المناعة غير موجود' end),
      jsonb_build_object('key','codes_hashed','ok', v_codes_plain = 0,
        'detail', case when v_codes_plain = 0 then 'الأكواد مجزَّأة SHA-256 (لا نص صريح)'
                       else v_codes_plain || ' عمود نصّ صريح للأكواد!' end),
      jsonb_build_object('key','activate_rate_limited','ok', true,
        'detail', 'تفعيل الأكواد مُقيَّد المعدّل (٨/ساعة/مستخدم)'),
      jsonb_build_object('key','admins_present','ok', v_admins > 0,
        'detail', v_admins || ' حساب إدارة'),
      jsonb_build_object('key','offline_grace','ok', v_grace > 0,
        'detail', 'فترة سماح دون اتصال: ' || v_grace || ' يوم'),
      -- المرحلة و — فحصٌ جديد: تلخيص حالة المفاتيح الفرعية للإنفاذ.
      jsonb_build_object('key','enforcement_subflags','ok', true,
        'detail', v_sub_detail)
    ),
    'posture', jsonb_build_object(
      'enforce', v_enforce,
      'trial_enabled', v_trial,
      'grace_days', v_grace,
      'admins', v_admins,
      'rate_limit_rows', v_rl_rows,
      'gated_users', v_gated,
      -- المرحلة و — المفاتيح الفرعية وعدّادات الأثر.
      'enforce_storage', v_enf_storage,
      'enforce_clinics', v_enf_clinics,
      'enforce_devices', v_enf_devices,
      'storage_over_users', v_storage_over,
      'clinics_over_users', v_clinics_over,
      'devices_over_users', v_devices_over
    )
  );
end;
$function$;

revoke all on function public.admin_security_audit() from public, anon;
grant execute on function public.admin_security_audit() to authenticated;
