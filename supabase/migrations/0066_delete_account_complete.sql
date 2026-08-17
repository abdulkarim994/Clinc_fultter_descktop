-- ============================================================================
--  م185 — حذف الحساب: رفع الحائط المانع وتغطية كل جداول المستخدم
-- ============================================================================
--
--  البلاغ (لقطة المالك، الهاتف والكمبيوتر معاً): زرّ «حذف الحساب نهائياً»
--  يفشل برسالة Postgres حرفية:
--      update or delete on table "users" violates foreign key constraint
--      "activation_codes_bound_user_id_fkey" on table "activation_codes"
--
--  ── التشخيص (فحص كل المفاتيح الأجنبية المشيرة إلى auth.users) ──────────
--  ثمانية عشر مفتاحاً: سبعة عشر منها ON DELETE CASCADE فتُنظَّف تلقائياً
--  (admins · devices · notifications · profiles · storage_usage ·
--  storage_usage_daily · subscriptions · user_data · user_presence +
--  جداول auth الداخلية)، و**واحدٌ فقط** بسلوك NO ACTION هو الحائط:
--  `activation_codes.bound_user_id`.
--
--  ── عيبٌ ثانٍ اكتُشف أثناء الفحص (تسريب بيانات صامت) ───────────────────
--  دالة 0031 تحذف من قائمة سبعة جداول ثابتة. ومنذ كتابتها ظهرت جداول
--  تحمل `user_id` **بلا** مفتاح أجنبي — فلا تُحذف ولا تتتالى، وأبرزها
--  جدولا نسخٍ احتياطية من مهاجرات قديمة يحملان بيانات مستخدمين فعلية:
--  `_bool_flags_backup_20260731` و`_thumb_cleanup_backup_20260730`.
--  فحتى لو نجح الحذف كانت بيانات المستخدم تبقى على الخادم.
--
--  ── ما تفعله هذه المهاجرة ─────────────────────────────────────────────
--    ١) المفتاح المانع ⇒ ON DELETE SET NULL: فلا يمنع الحذف أبداً، لا من
--       التطبيق ولا من لوحة الإدارة ولا من حذفٍ مباشر.
--    ٢) `delete_my_account` تُعاد كتابتها:
--       • تُجرّد أكواد تنشيط المستخدم من هويته (bound_user_id/bound_email)
--         **مع إبقاء حالتها `used`** — قرار أمني مقصود: إعادة الكود
--         صالحاً عند حذف الحساب تفتح ثغرة تجربةٍ لا نهائية (تنشيط ← حذف
--         ← تنشيط). ويبقى في `note` أثرٌ أن صاحبه حسابٌ محذوف.
--       • تحذف من **كل** جداول المستخدم بما فيها جدولا النسخ القديمة.
--       • تنتهي بحذف صفّ auth.users فيتتالى الباقي.
--    ٣) دالة تحقّق `account_purge_gaps()` تُدرِج أي جدول عام يحمل عمود
--       هوية المستخدم وليس مشمولاً بالحذف ولا بالتتالي. المتوقع: صفر
--       صفوف — وهي حارس «لا يتكرر» لأي جدول يُضاف مستقبلاً.
--
--  ── التحقق بعد التطبيق ────────────────────────────────────────────────
--    select confdeltype from pg_constraint
--     where conname = 'activation_codes_bound_user_id_fkey';   -- المتوقع n
--    select * from public.account_purge_gaps();                -- صفر صفوف
-- ============================================================================

-- ── ١) رفع الحائط: المفتاح المانع يصير SET NULL ─────────────────────────
ALTER TABLE public.activation_codes
  DROP CONSTRAINT IF EXISTS activation_codes_bound_user_id_fkey;

ALTER TABLE public.activation_codes
  ADD CONSTRAINT activation_codes_bound_user_id_fkey
  FOREIGN KEY (bound_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

COMMENT ON CONSTRAINT activation_codes_bound_user_id_fkey
  ON public.activation_codes IS
  'م185 — SET NULL: حذف الحساب لا يجوز أن يُمنع بكودِ تنشيطٍ مرتبط. '
  'الكود يبقى مستهلَكاً (status=used) مجرَّداً من هوية صاحبه.';

-- ── ٢) دالة الحذف الكاملة ───────────────────────────────────────────────
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

  -- م185 — أكواد التنشيط: تجريدٌ من الهوية لا حذفاً. حذفُ الصف يمحو سجلّ
  -- الترخيص عند الإدارة، وإعادةُ الكود صالحاً تفتح ثغرة تجربةٍ لا نهائية.
  IF to_regclass('public.activation_codes') IS NOT NULL THEN
    UPDATE public.activation_codes
       SET bound_user_id = NULL,
           bound_email   = NULL,
           note          = btrim(coalesce(note, '') || ' [حساب محذوف]'),
           updated_at    = now()
     WHERE bound_user_id = v_uid;
  END IF;

  -- بيانات المستدعي حصراً — user_id = auth.uid() في كل جدول.
  -- 🔴 عند إضافة أي جدول يحمل user_id: أضِفه هنا، أو اجعل مفتاحه الأجنبي
  --    ON DELETE CASCADE. حارس account_purge_gaps() أدناه يكشف النسيان.
  FOREACH t IN ARRAY ARRAY[
    'sync_rows',                      -- الشرائح تتبع الأصل بالتتالي
    'applied_ops',
    'device_cursors',
    'device_sync_state',
    'archive_log',
    'archive_horizon',
    'audit_log',
    -- م185 — بقايا مهاجرات قديمة تحمل بيانات مستخدمين (كانت تبقى بعد الحذف)
    '_bool_flags_backup_20260731',
    '_thumb_cleanup_backup_20260730'
  ] LOOP
    IF to_regclass('public.' || t) IS NOT NULL THEN
      EXECUTE format('DELETE FROM public.%I WHERE user_id = $1', t)
        USING v_uid;
    END IF;
  END LOOP;

  -- صفّ المستخدم أخيراً: يتتالى معه كل ما ارتبط به بـCASCADE.
  DELETE FROM auth.users WHERE id = v_uid;
END;
$$;

REVOKE ALL ON FUNCTION public.delete_my_account() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.delete_my_account() TO authenticated;

COMMENT ON FUNCTION public.delete_my_account() IS
  'م185 — حذف حساب المستدعي بكل بياناته: تجريد أكواد التنشيط من هويته '
  '(مع إبقائها مستهلَكة)، ثم حذف جداول بياناته كلها، ثم صفّ auth.users '
  'فيتتالى الباقي. SECURITY DEFINER بمسار بحث مثبَّت، للمصادَق حصراً.';

-- ── ٣) حارس «لا يتكرر»: فجوات التطهير ───────────────────────────────────
--  يُدرج كل جدولٍ عام يحمل عمود هوية مستخدم وليس مشمولاً بقائمة الحذف
--  أعلاه ولا بمفتاحٍ أجنبي متتالٍ. أي صفٍّ يعيده = بيانات تبقى بعد حذف
--  الحساب. الشرائح (sync_rows_p%) مستثناة: تتبع أصلها بالتتالي.
CREATE OR REPLACE FUNCTION public.account_purge_gaps()
RETURNS TABLE (table_name text, column_name text, reason text)
LANGUAGE sql
STABLE
SET search_path = public, pg_catalog, pg_temp
AS $$
  WITH purged AS (
    SELECT unnest(ARRAY[
      'sync_rows', 'applied_ops', 'device_cursors', 'device_sync_state',
      'archive_log', 'archive_horizon', 'audit_log',
      '_bool_flags_backup_20260731', '_thumb_cleanup_backup_20260730'
    ]) AS t
  ),
  cols AS (
    SELECT c.relname::text AS t, a.attname::text AS col
      FROM pg_class c
      JOIN pg_namespace n ON n.oid = c.relnamespace
      JOIN pg_attribute a ON a.attrelid = c.oid AND a.attnum > 0
                         AND NOT a.attisdropped
     WHERE n.nspname = 'public'
       AND c.relkind IN ('r', 'p')
       AND a.attname IN ('user_id', 'owner_uid', 'bound_user_id')
       AND c.relname NOT LIKE 'sync_rows_p%'
  ),
  cascaded AS (
    SELECT src.relname::text AS t,
           (SELECT a.attname::text FROM unnest(con.conkey) k
              JOIN pg_attribute a ON a.attrelid = con.conrelid
                                 AND a.attnum = k LIMIT 1) AS col
      FROM pg_constraint con
      JOIN pg_class src ON src.oid = con.conrelid
      JOIN pg_namespace n ON n.oid = src.relnamespace
      JOIN pg_class tgt ON tgt.oid = con.confrelid
      JOIN pg_namespace tn ON tn.oid = tgt.relnamespace
     WHERE con.contype = 'f' AND con.confdeltype = 'c'
       AND tgt.relname = 'users' AND tn.nspname = 'auth'
       AND n.nspname = 'public'
  )
  SELECT cols.t, cols.col,
         'ليس في قائمة الحذف ولا مفتاحه الأجنبي متتالياً'::text
    FROM cols
   WHERE NOT EXISTS (SELECT 1 FROM purged p WHERE p.t = cols.t)
     AND NOT EXISTS (SELECT 1 FROM cascaded c
                      WHERE c.t = cols.t AND c.col = cols.col)
     -- أكواد التنشيط تُعالَج بالتجريد لا بالحذف (وSET NULL يحرسها).
     AND NOT (cols.t = 'activation_codes' AND cols.col = 'bound_user_id')
   ORDER BY cols.t, cols.col;
$$;

COMMENT ON FUNCTION public.account_purge_gaps() IS
  'م185 — حارس تطهير الحساب: يُدرج أي جدول يحمل هوية مستخدم ولا يُنظَّف '
  'عند حذف الحساب. المتوقع دائماً: صفر صفوف.';

GRANT EXECUTE ON FUNCTION public.account_purge_gaps() TO authenticated;
