-- ============================================================================
--  م68/دفعة ثانٍ-أ — تثبيت search_path لكل دوال المخطط العام
-- ============================================================================
--
--  ⚠ هذه المهاجرة **طُبِّقت فعلاً** على قاعدة الإنتاج (Dentaldk /
--    <PROJECT-REF>) بتاريخ 2026-07-30 تحت الاسم
--    `harden_function_search_path_and_anon_grants` (20260730023432).
--    وُثِّقت هنا كي لا تبقى حالة القاعدة خارج المستودع.
--
--  العلة
--  ─────
--  سبع عشرة دالة في `public` كانت بلا `search_path` مثبَّت. الدالة التي
--  تعمل بـ SECURITY DEFINER وبـ search_path متغيّر تُنفَّذ بصلاحيات مالكها
--  بينما **المهاجم يتحكم بأي جدول أو عامل تراه**: يكفي أن ينشئ
--  `public.now()` أو نوعاً أو عاملاً في مخطط يسبق `public` في مسار البحث
--  ليُخطف تنفيذها. هذا نمط تصعيد صلاحيات معروف
--  (CVE-2018-1058 وما تلاه) لا احتمال نظري.
--
--  حتى الدوال بـ SECURITY INVOKER تستفيد: تثبيت المسار يجعل خطة التنفيذ
--  حتمية ولا تتغيّر بتغيّر جلسة المستدعي.
--
--  `extensions` مُضمَّن لأن Supabase يضع pgcrypto وغيرها هناك؛ حذفه يكسر
--  أي دالة تستدعي gen_random_uuid أو digest.
--
--  التحقق بعد التطبيق
--  ──────────────────
--    SELECT count(*) FROM pg_proc p
--    JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname = 'public' AND p.prokind = 'f'
--      AND NOT EXISTS (
--        SELECT 1 FROM unnest(coalesce(p.proconfig,'{}')) c
--        WHERE c LIKE 'search_path=%');
--    -- النتيجة المرصودة: 0 من أصل 17
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prokind = 'f'
      AND NOT EXISTS (
        SELECT 1
        FROM unnest(coalesce(p.proconfig, '{}'::text[])) c
        WHERE c LIKE 'search_path=%'
      )
  LOOP
    EXECUTE format(
      'ALTER FUNCTION %s SET search_path = public, extensions, pg_temp',
      r.sig
    );
  END LOOP;
END $$;
