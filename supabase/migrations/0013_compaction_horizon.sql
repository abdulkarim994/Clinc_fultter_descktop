-- ============================================================================
--  م65 — أفق الضغط الآمن لكل الأجهزة (إحياء تقليم شواهد الحذف)
-- ============================================================================
--
--  العلة
--  ─────
--  وحدة `compaction.dart` مبنية بإتقان و`runCompaction` مستدعاة فعلاً بعد كل
--  سحب (pull.dart) — لكنها **شيفرة ميتة**: الأفق يُقرأ من المفتاح
--  `sync.compaction.horizon`، ولا يكتبه أي موضع في المشروع، فيعود صفراً
--  دائماً و`runCompaction` تخرج فوراً. النتيجة أن كل شاهدة حذف (دفعة ملغاة،
--  مرحلة علاج محذوفة، صف طابور منقضٍ) تبقى داخل كتلة الصف **إلى الأبد**،
--  ويُعاد دفعها وتخزينها مع كل تحديث لاحق للصف.
--
--  الأثر: السعة تنقسم على اثنين كل سنة — 10.5 مشترك في الأولى، 5.2 في
--  الثانية، 3.5 في الثالثة. الأرشفة تثبّتها.
--
--  الحل
--  ────
--  الأفق = **أدنى `server_seq` طبّقته كل أجهزة الحساب**. ما دون ذلك بلغ
--  الجميع فيجوز تقليمه. وهذا يقتضي أن يعرف الخادم مؤشر كل جهاز — وهو ما لم
--  يكن يبلّغه أحد. تضيفه هذه الهجرة:
--
--    1) جدول `device_cursors` — مؤشر مطبَّق لكل (مستخدم، جهاز)
--    2) تحديثه ضمن `pull_changes` من `p_lower` الوارد
--    3) إرجاع `horizon` في استجابة السحب
--
--  الأمان
--  ──────
--  • جهاز صامت أطول من `p_stale_days` يُستبعد من الحساب، وإلا جمّد لوحه
--    المهجور الأفقَ إلى الأبد. الافتراضي ثلاثون يوماً — أوسع بكثير من أي
--    انقطاع معقول، وأي جهاز يعود بعدها يكون قد فقد شواهد قُلِّمت، لذا
--    الاستبعاد متحفّظ عمداً.
--  • جهاز واحد فقط ⇒ الأفق مؤشره هو (لا شيء يُنتظر).
--  • لا أجهزة مسجّلة ⇒ يعود صفراً ⇒ الضغط معطّل (فشل آمن).
--  • العميل لا يكتب إلا أفقاً موجباً يتقدّم للأمام (pull.dart).
-- ============================================================================

CREATE TABLE IF NOT EXISTS device_cursors (
  user_id    uuid        NOT NULL,
  device_id  text        NOT NULL,
  applied_seq bigint     NOT NULL DEFAULT 0,
  seen_at    timestamptz NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, device_id)
);

CREATE INDEX IF NOT EXISTS idx_device_cursors_user
  ON device_cursors (user_id, seen_at);

ALTER TABLE device_cursors ENABLE ROW LEVEL SECURITY;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
     WHERE tablename = 'device_cursors' AND policyname = 'own_cursors'
  ) THEN
    CREATE POLICY own_cursors ON device_cursors
      USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
  END IF;
END $$;

-- تسجيل مؤشر جهاز — يُنادى من داخل pull_changes.
CREATE OR REPLACE FUNCTION touch_device_cursor(
  p_device_id text,
  p_applied   bigint
) RETURNS void
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO device_cursors (user_id, device_id, applied_seq, seen_at)
  VALUES (auth.uid(), p_device_id, GREATEST(p_applied, 0), now())
  ON CONFLICT (user_id, device_id) DO UPDATE
    SET applied_seq = GREATEST(device_cursors.applied_seq,
                               EXCLUDED.applied_seq),  -- لا يتراجع أبداً
        seen_at     = now();
$$;

-- حساب الأفق: أدنى مؤشر بين الأجهزة الحيّة وحدها.
CREATE OR REPLACE FUNCTION compaction_horizon(
  p_stale_days int DEFAULT 30
) RETURNS bigint
LANGUAGE sql STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(MIN(applied_seq), 0)
    FROM device_cursors
   WHERE user_id = auth.uid()
     AND seen_at > now() - make_interval(days => p_stale_days);
$$;

REVOKE ALL ON FUNCTION touch_device_cursor(text, bigint) FROM PUBLIC;
REVOKE ALL ON FUNCTION compaction_horizon(int)           FROM PUBLIC;
DO $$
DECLARE r text;
BEGIN
  FOREACH r IN ARRAY ARRAY['authenticated'] LOOP
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = r) THEN
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION touch_device_cursor(text,bigint) TO %I', r);
      EXECUTE format(
        'GRANT EXECUTE ON FUNCTION compaction_horizon(int) TO %I', r);
    END IF;
  END LOOP;
END $$;

-- ── الربط بـ pull_changes ───────────────────────────────────────────────────
--
--  عدّل `pull_changes` (المعرّفة في 0011_pull_changes_gapfree.sql) بإضافة
--  وسيط معرّف الجهاز، وبسطرين قبل الإرجاع:
--
--      PERFORM touch_device_cursor(p_device_id, p_lower);
--      ...
--      RETURN jsonb_build_object(
--        'rows',    v_rows,
--        'safe',    v_safe,
--        'horizon', compaction_horizon(30)   -- ← الجديد
--      );
--
--  وحتى قبل تعديلها: مفتاح `horizon` الغائب يُقرأ null على العميل فيبقى
--  الضغط معطّلاً — أي أن نشر هذه الهجرة وحدها آمن تماماً ولا يغيّر سلوكاً.
