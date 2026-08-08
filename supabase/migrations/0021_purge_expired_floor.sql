-- ============================================================================
--  م71 — رفع أرضية purge_expired من صفر إلى سبعة أيام
-- ============================================================================
--
--  الدالة موجودة منذ زمن بلا مستدعٍ؛ م71 يوصلها بالعميل (كنسة أسبوعية
--  بـ p_retain_days = 30 تحذف شواهد القبور القديمة حذفاً فعلياً).
--
--  العلة المُصلَحة هنا: الأرضية القديمة كانت `greatest(coalesce(p, 7), 0)`
--  — أي أن عميلاً معطوباً أو خبيثاً يمرر 0 فيمحو شواهد قبور **طازجة**
--  قبل أن تصل بقية الأجهزة، فيعود المحذوف حياً عندها إلى الأبد (الشاهد
--  هو الرسالة، ومحوه قبل التسليم = ضياع الحذف). الأرضية الجديدة 7 أيام
--  تُفرض خادمياً مهما ادّعى العميل — نفس فلسفة أرضية التسعين يوماً في
--  archive_rows (0020).
--
--  ما لا يتغير: الملكية (user_id = auth.uid())، المشطوب فقط
--  (_deleted = true)، الصلاحيات (authenticated فقط — 0015)، وsearch_path
--  المثبّت (0014) يُعاد نصاً لأن CREATE OR REPLACE يمحو الإعدادات.
--
--  التحقق بعد التطبيق:
--    نداء بـ p_retain_days = 0 على شاهد عمره 3 أيام ⇒ لا يُحذف.
--    نداء بـ 30 على شاهد عمره 40 يوماً ⇒ يُحذف. شاهد الغير لا يُمسّ.
-- ============================================================================

-- ملاحظة: الدالة الأصلية على الإنتاج لها DEFAULT على المعامل، وREPLACE لا
-- يستطيع إزالته (42P13) — يُبقى عليه (7، منسجماً مع الأرضية).
CREATE OR REPLACE FUNCTION public.purge_expired(p_retain_days integer DEFAULT 7)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  n int;
BEGIN
  DELETE FROM sync_rows
  WHERE user_id = auth.uid()
    AND _deleted = true
    AND updated_at <
        now() - make_interval(days => GREATEST(coalesce(p_retain_days, 7), 7));
  GET DIAGNOSTICS n = ROW_COUNT;
  RETURN jsonb_build_object('purged', n);
END;
$$;

-- الصلاحيات كما رسّختها 0015 — تُعاد نصاً احترازاً من إرث CREATE OR REPLACE.
REVOKE ALL ON FUNCTION public.purge_expired(integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.purge_expired(integer)
  TO authenticated, service_role;
