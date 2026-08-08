-- ============================================================================
--  م68/دفعة ثانٍ-أ — تسريع RLS على المسار الساخن ودمج السياسات المكرّرة
-- ============================================================================
--
--  ⚠ طُبِّقت على الإنتاج 2026-07-30 باسم
--    `optimize_rls_initplan_and_dedupe_policies_indexes` (20260730023800).
--
--  ═══ العلة الأولى: auth.uid() لكل صف ═══
--
--  سياسات RLS كانت مكتوبة `user_id = auth.uid()`. المخطِّط يعامل
--  `auth.uid()` هنا مُعامَلةَ تعبير متغيّر لكل صف، فيستدعيها **مرة لكل صف
--  ممسوح**. على جدول فيه 149,892 صفاً هذا مئات آلاف الاستدعاءات
--  للاستعلام الواحد. والأسوأ من الكلفة المباشرة أن الشرط لا يصلح عندئذٍ
--  شرطَ فهرس، فيهبط المسح إلى Seq Scan + Filter.
--
--  لفّها في `(SELECT auth.uid())` يحوّلها InitPlan يُقيَّم **مرة واحدة**،
--  ويصير الناتج ثابتاً يقبله الفهرس شرطاً.
--
--  القياس على الإنتاج بعد التطبيق (EXPLAIN ANALYZE بهوية مصادَقة حقيقية):
--
--      InitPlan 1
--        ->  Result (actual time=0.019..0.020 rows=1 loops=1)   ← مرة واحدة
--      ->  Index Scan using sync_rows_p61_user_id_txid_server_seq_idx
--            Index Cond: ((user_id = (InitPlan 1).col1) AND (server_seq > 0))
--      Execution Time: 8.230 ms
--
--  والشرط صار داخل `Index Cond` لا `Filter` — وهو بيت القصيد. الشرائح
--  الثلاث والستون الأخرى: "never executed".
--
--  ═══ العلة الثانية: سياسات متعدّدة متساهلة ═══
--
--  `user_data` كان يحمل **تسع** سياسات لأربعة أوامر: بقايا أجيال متتالية
--  من المهاجرات لم يُحذف سابقها. PostgreSQL يقيّم **كل** سياسة متساهلة
--  ويجمعها بـ OR، فالتكرار كلفة صافية بلا أثر دلالي. دُمجت إلى أربع،
--  واحدة لكل أمر.
--
--  ═══ فهرس وقيد مكرّران ═══
--
--  حُذف فهرس مطابق تماماً لآخر وقيد فريد مكرّر — نسخة واحدة تبقى.
--
--  ═══ الأثر المرصود على المدقّق ═══
--
--    مدقّق الأداء : 36 تحذيراً ← 0
--    مدقّق الأمن  : 20 تحذيراً ← 3   (اثنان مقصودان، وواحد يحتاج اللوحة)
--
--  ═══ إثبات عدم كسر العزل ═══
--
--  إعادة كتابة سياسة SELECT على المسار الساخن تستوجب إثباتاً لا ادّعاء.
--  اختبار سلبي بهويتين حقيقيتين بعد التطبيق:
--
--    user1 يرى صفوفه           : 149,006
--    user1 يرى صفوف user2      : 0        ← المطلوب
--    user2 يرى صفوفه           : 325
--    anon يرى                  : 0        ← المطلوب
--
--  ملاحظة: لا سياسة DELETE على sync_rows، وهذا بالتصميم — الحذف يتم
--  بشواهد القبور (tombstones) لا بحذف فعلي، كي تنتشر عبر المزامنة.
-- ============================================================================

-- ── sync_rows: الجدول المقسَّم (المسار الساخن) ──────────────────────────────
DROP POLICY IF EXISTS sync_rows_select ON public.sync_rows;
DROP POLICY IF EXISTS sync_rows_insert ON public.sync_rows;
DROP POLICY IF EXISTS sync_rows_update ON public.sync_rows;

CREATE POLICY sync_rows_select ON public.sync_rows
  FOR SELECT USING (user_id = (SELECT auth.uid()));
CREATE POLICY sync_rows_insert ON public.sync_rows
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY sync_rows_update ON public.sync_rows
  FOR UPDATE USING (user_id = (SELECT auth.uid()))
             WITH CHECK (user_id = (SELECT auth.uid()));

-- ── sync_rows_legacy: جدول ما قبل التقسيم، ما زال يُقرأ ─────────────────────
DROP POLICY IF EXISTS sync_rows_select ON public.sync_rows_legacy;
DROP POLICY IF EXISTS sync_rows_insert ON public.sync_rows_legacy;
DROP POLICY IF EXISTS sync_rows_update ON public.sync_rows_legacy;

CREATE POLICY sync_rows_select ON public.sync_rows_legacy
  FOR SELECT USING (user_id = (SELECT auth.uid()));
CREATE POLICY sync_rows_insert ON public.sync_rows_legacy
  FOR INSERT WITH CHECK (user_id = (SELECT auth.uid()));
CREATE POLICY sync_rows_update ON public.sync_rows_legacy
  FOR UPDATE USING (user_id = (SELECT auth.uid()))
             WITH CHECK (user_id = (SELECT auth.uid()));

-- ── applied_ops: سياسة واحدة لكل الأوامر ────────────────────────────────────
DROP POLICY IF EXISTS applied_ops_rw ON public.applied_ops;

CREATE POLICY applied_ops_rw ON public.applied_ops
  FOR ALL USING (user_id = (SELECT auth.uid()))
          WITH CHECK (user_id = (SELECT auth.uid()));

-- ── user_data: تسع سياسات ← أربع ────────────────────────────────────────────
DO $$
DECLARE p record;
BEGIN
  FOR p IN SELECT policyname FROM pg_policies
           WHERE schemaname='public' AND tablename='user_data'
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.user_data', p.policyname);
  END LOOP;
END $$;

CREATE POLICY user_data_select_own ON public.user_data
  FOR SELECT USING ((SELECT auth.uid()) = user_id);
CREATE POLICY user_data_insert_own ON public.user_data
  FOR INSERT WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY user_data_update_own ON public.user_data
  FOR UPDATE USING ((SELECT auth.uid()) = user_id)
             WITH CHECK ((SELECT auth.uid()) = user_id);
CREATE POLICY user_data_delete_own ON public.user_data
  FOR DELETE USING ((SELECT auth.uid()) = user_id);
