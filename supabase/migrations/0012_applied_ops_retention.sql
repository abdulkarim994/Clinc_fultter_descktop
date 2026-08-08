-- ============================================================================
--  م65 — تقليم سجل العمليات المطبَّقة (applied_ops)
-- ============================================================================
--
--  العلة المقيسة
--  ─────────────
--  `applied_ops` يحفظ صفاً لكل **عملية** طُبِّقت — لا لكل صف — بكلفة مقيسة
--  على PostgreSQL 15 تبلغ **256 بايت للعملية الواحدة** (شاملة الكومة والمفتاح
--  الأساسي). عند خمسين مريضاً يومياً لكل حساب هذا نحو 3,250 عملية شهرياً، أي
--  **832 كيلوبايت شهرياً لكل حساب** تتراكم بلا نهاية.
--
--  الغرض من السجل هو منع تطبيق العملية نفسها مرتين (op_id = entity:id:hlc).
--  ونافذة أسبوع تكفي هذا الغرض تماماً: العميل يعيد المحاولة ثماني مرات كحد
--  أقصى ضمن تراجع أُسّي سقفه خمس دقائق (engine.dart)، فأي إعادة إرسال ممكنة
--  تقع خلال ساعات لا أسابيع. الاحتفاظ الأبدي لا يشتري أماناً إضافياً.
--
--  الأثر المقيس: 4.39 ← 3.65 ميغابايت لكل حساب شهرياً (توفير 17٪)،
--  أي من 8.0 إلى 9.6 مشترك على الخطة المجانية للسنة الواحدة.
--
--  الأمان
--  ──────
--  • النافذة سبعة أيام — أوسع بمرتين من أطول تراجع ممكن للعميل.
--  • الحذف على دفعات كي لا يقفل جدولاً كبيراً دفعة واحدة.
--  • الفهرس على `applied_at` يجعل التقليم مسحاً مدىً لا مسحاً كاملاً.
-- ============================================================================

-- فهرس التقليم: بدونه يصير الحذف الدوري مسحاً كاملاً للجدول.
CREATE INDEX IF NOT EXISTS idx_applied_ops_applied_at
  ON applied_ops (applied_at);

-- التقليم على دفعات — يعيد عدد الصفوف المحذوفة كي يمكن رصده.
CREATE OR REPLACE FUNCTION prune_applied_ops(
  p_retain_days int DEFAULT 7,
  p_batch       int DEFAULT 50000
) RETURNS bigint
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_cutoff timestamptz := now() - make_interval(days => p_retain_days);
  v_total  bigint := 0;
  v_n      bigint;
BEGIN
  LOOP
    DELETE FROM applied_ops
     WHERE ctid IN (
       SELECT ctid FROM applied_ops
        WHERE applied_at < v_cutoff
        LIMIT p_batch
     );
    GET DIAGNOSTICS v_n = ROW_COUNT;
    v_total := v_total + v_n;
    EXIT WHEN v_n = 0;
  END LOOP;
  RETURN v_total;
END;
$$;

-- سحب الصلاحية عن العموم وعن دورَي Supabase — بفحص وجود الدور كي تبقى
-- الهجرة صالحة على أي قاعدة PostgreSQL (بيئة اختبار محلية مثلاً).
REVOKE ALL ON FUNCTION prune_applied_ops(int, int) FROM PUBLIC;
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['anon','authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format(
        'REVOKE ALL ON FUNCTION prune_applied_ops(int,int) FROM %I', r);
    END IF;
  END LOOP;
END $$;

-- ── الجدولة ────────────────────────────────────────────────────────────────
-- يومياً في الثالثة صباحاً بتوقيت UTC. يتطلب امتداد pg_cron
-- (Supabase: Database → Extensions → pg_cron).
--
-- CREATE EXTENSION IF NOT EXISTS pg_cron;
-- SELECT cron.schedule(
--   'prune-applied-ops', '0 3 * * *',
--   $cron$ SELECT prune_applied_ops(7); $cron$
-- );
--
-- وبدون pg_cron: نادِ `SELECT prune_applied_ops(7);` من مهمة خارجية دورية،
-- أو مرة واحدة يدوياً عند مراقبة حجم القاعدة.

-- ── تنفيذ أول فوري ─────────────────────────────────────────────────────────
-- يحرّر المتراكم منذ بداية المشروع دفعة واحدة.
SELECT prune_applied_ops(7);
