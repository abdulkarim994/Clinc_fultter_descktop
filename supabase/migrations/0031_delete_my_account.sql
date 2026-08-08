-- ============================================================================
--  م93 — حذف الحساب الذاتي: دالة delete_my_account()
-- ============================================================================
--
--  ✅ هذه المهاجرة **طُبِّقت فعلاً** على قاعدة الإنتاج (Dentaldk /
--    qajgqatflmiiwqznxfha) بتاريخ 2026-08-01 تحت الاسم `delete_my_account`
--    (20260801132255) — عبر خادم Supabase MCP الموصول بالوكيل. تُحُقِّق
--    منها ثلاثياً بعد التطبيق: pg_proc (prosecdef=true + search_path
--    مثبَّت)، وroutine_privileges (التنفيذ لـauthenticated/postgres/
--    service_role حصراً — لا anon)، ونداءٌ خارجي بمفتاح anon بلا هوية
--    رُدّ بـ42501 «permission denied» لا PGRST202 — أي منشورةٌ ومحمية.
--    وُثِّقت هنا كي لا تبقى حالة القاعدة خارج المستودع (نمط 0014).
--
--  الغرض
--  ─────
--  مفتاح anon لا يستطيع حذف صفّ `auth.users` — بالتصميم. فيحتاج «حذف
--  الحساب» من داخل التطبيق دالةً بصلاحيات المالك (SECURITY DEFINER —
--  نفس نمط archive_rows/0020 وprofiles/0030) تحذف **بيانات المستدعي
--  حصراً** (`auth.uid()`) ثم صفَّه في auth.users.
--
--  ما تحذفه — كل أثرٍ للمستخدم على الخادم
--  ─────────────────────────────────────────
--    • صفوف البيانات المتزامنة: sync_rows (الشرائح تتبع الأصل).
--    • عمليات المزامنة والمؤشرات: applied_ops، device_cursors،
--      device_sync_state.
--    • سجلّات التشغيل: archive_log، archive_horizon، audit_log.
--    • profiles: تسقط تلقائياً بالتتالي (FK on delete cascade مع
--      auth.users — انظر 0030).
--    • صف auth.users نفسه — فيبطل الدخول ويُبطل التتالي كلَّ ما يتبعه.
--
--  ملاحظتا أمان
--  ────────────
--    ١) audit_log «لا يقبل إلا الإضافة» (0026) عبر سحب UPDATE/DELETE من
--       الأدوار — وهذا يستهدف عبثَ صاحبِ الحساب أثناء حياته. محوُ السجل
--       عند **محو الحساب كله** مقصود (محو بيانات كامل)، والدالة بمالكها
--       postgres تملك الحذف شرعاً.
--    ٢) الحذف من الجداول ديناميكي بفحص to_regclass: جدول غائب في نسخة
--       أقدم/أحدث لا يكسر الدالة — تحذف الموجود وتتخطى الغائب.
--
--  لماذا الحقيقة على الخادم أولاً
--  ───────────────────────────────
--  التطبيق ينادي هذه الدالة **قبل** تطهير R2 والمسح المحلي: لو انقطع
--  بعد نجاحها فالحسابُ زال من المصدر، وبقايا R2 كائناتٌ يتيمة يطهّرها
--  التطبيق في نفس الجلسة (رمز الوصول يبقى صالح التوقيع حتى انتهائه).
--
--  التحقق بعد التطبيق
--  ──────────────────
--    select proname, prosecdef,
--           (select array_agg(c) from unnest(coalesce(proconfig,'{}')) c
--             where c like 'search_path=%') as sp
--      from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--     where n.nspname = 'public' and proname = 'delete_my_account';
--    -- المتوقع: صفٌّ واحد، prosecdef = true، وsearch_path مثبَّت.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.delete_my_account()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_uid uuid := auth.uid();
  t     text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not authenticated' USING ERRCODE = '28000';
  END IF;

  -- بيانات المستدعي حصراً — user_id = auth.uid() في كل جدول.
  FOREACH t IN ARRAY ARRAY[
    'sync_rows',
    'applied_ops',
    'device_cursors',
    'device_sync_state',
    'archive_log',
    'archive_horizon',
    'audit_log'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DELETE FROM public.%I WHERE user_id = $1', t)
        USING v_uid;
    END IF;
  END LOOP;

  -- profiles تسقط بالتتالي مع هذا الصف (0030: on delete cascade).
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

-- نفس نمط 0015: لا تنفيذ عاماً على دوال SECURITY DEFINER — المصادَق فقط.
REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

COMMENT ON FUNCTION public.delete_my_account() IS
  'م93 — حذف حساب المستدعي بكامل بياناته (sync_rows وملحقاتها ثم '
  'auth.users؛ profiles بالتتالي). SECURITY DEFINER بمسار بحث مثبَّت، '
  'التنفيذ للمصادَق حصراً.';
