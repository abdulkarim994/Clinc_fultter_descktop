-- ============================================================================
--  م68/دفعة ثانٍ-أ — سحب EXECUTE من PUBLIC عن دوال SECURITY DEFINER
-- ============================================================================
--
--  ⚠ طُبِّقت على الإنتاج 2026-07-30 باسم
--    `revoke_public_execute_on_security_definer_fns` (20260730023521).
--
--  الدرس الذي فرض هذه المهاجرة
--  ───────────────────────────
--  المحاولة الأولى كانت `REVOKE EXECUTE ... FROM anon` وأعادت `success`.
--  والتحقق بعدها أظهر `anon_can_exec = true` رغم ذلك — أي أن السحب كان
--  **عملية صامتة بلا أثر**. السبب في قائمة التحكم بالوصول:
--
--      purge_expired  =X/postgres
--
--  لا اسم دور قبل `=X`، وهذا في ترميز ACL يعني منحةً لـ **PUBLIC**.
--  و`anon` ينفّذ بحكم عضويته الضمنية في PUBLIC لا بمنحة باسمه، فالسحب
--  «من anon» لم يجد ما يسحبه. العلاج هو السحب من PUBLIC ثم إعادة المنح
--  صراحةً لمن يحتاجها.
--
--  الخلاصة العملية: لا تثق بـ `success` من عبارة REVOKE — تحقّق دائماً بـ
--  `has_function_privilege` بعدها.
--
--  لماذا بقي `authenticated` يملك purge_expired و purge_rows
--  ─────────────────────────────────────────────────────────
--  هذا **مقصود**. الدالتان تنظّفان بيانات المستدعي نفسه وكلتاهما مقيّدة
--  داخلياً بـ `user_id = auth.uid()`، والتطبيق يستدعيهما مباشرةً من
--  العميل عند الضغط. مدقّق Supabase يبقى يشير إليهما بـ WARN — وهذا
--  إشعار مقبول لا خلل، لأن البديل (نقلهما خلف Edge Function) يضيف
--  زمن استجابة ونقطة فشل بلا مكسب أمني حقيقي.
--
--  التحقق
--  ──────
--    SELECT p.proname,
--           has_function_privilege('anon', p.oid, 'EXECUTE') AS anon_can_exec
--    FROM pg_proc p
--    JOIN pg_namespace n ON n.oid = p.pronamespace
--    WHERE n.nspname='public' AND p.prosecdef;
--    -- المرصود: anon_can_exec = false على الثلاث جميعاً
-- ============================================================================

DO $$
DECLARE
  r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig, p.proname
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND p.prosecdef
  LOOP
    -- الجذر: المنحة على PUBLIC، لا على anon باسمه.
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC', r.sig);
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM anon', r.sig);

    -- إعادة المنح صراحةً لمن يحتاج: التطبيق يستدعي هذه الدوال بهوية
    -- مصادَقة، وكلٌّ منها مقيّدة داخلياً بـ user_id = auth.uid().
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO authenticated', r.sig);
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO service_role', r.sig);
  END LOOP;
END $$;
