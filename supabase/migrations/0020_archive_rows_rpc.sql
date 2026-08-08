-- ============================================================================
--  م70 — نداء الأرشفة الباردة: archive_rows
-- ============================================================================
--
--  العميل (ColdArchive في التطبيق) يحزم الصفوف القديمة إلى R2 ويتحقق من
--  وصول الحزمة ببصمة SHA-256، **ثم** يستدعي هذه الدالة لحذفها من النافذة
--  الساخنة. حذف بلا شواهد قبور عمداً: أرشفةٌ لا حذفٌ — الأجهزة تحتفظ
--  بنسخها المحلية كاملة، والحزم على R2 هي النسخة الباردة.
--
--  ضمانات خادمية مستقلة عن العميل — عميل معطوب أو خبيث لا يستطيع:
--    · لمس صفوف غيره        : user_id = auth.uid() دائماً
--    · حذف كيان محظور        : قائمة سماح صريحة (records/appointments/xrays)
--                              — patients وdebts وsettings مرفوضة بنيوياً
--    · حذف صف حديث           : أرضية عمر 90 يوماً تُفرض بـ GREATEST هنا،
--                              مهما ادّعى p_min_age_days
--    · إغراق النداء          : سقف 10,000 عنصر بالطلب الواحد
--
--  الدالة idempotent: صف محذوف أصلاً لا يُحتسب، فإعادة محاولة العميل بعد
--  فشلٍ في منتصف الخط آمنة دائماً.
--
--  سجل صغير (archive_log) لكل عملية: مقدار المحذوف وتوزيعه — للدعم
--  والمراقبة، بضع عشرات البايتات للتشغيلة، ولا وصول مباشراً له عبر REST
--  (بلا منح وبـ RLS بلا سياسات — النمط المُثبت في 0017).
-- ============================================================================

CREATE TABLE IF NOT EXISTS public.archive_log (
  id          bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY,
  user_id     uuid        NOT NULL,
  archived_at timestamptz NOT NULL DEFAULT now(),
  n_rows      integer     NOT NULL,
  entities    jsonb
);
REVOKE ALL ON public.archive_log FROM PUBLIC, anon, authenticated;
ALTER TABLE public.archive_log ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.archive_rows(
  p_items jsonb,
  p_min_age_days integer DEFAULT 90
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions, pg_temp
AS $$
DECLARE
  v_uid  uuid := auth.uid();
  v_cut  timestamptz;
  v_n    integer := 0;
  v_ents jsonb;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'auth required';
  END IF;
  IF p_items IS NULL OR jsonb_typeof(p_items) <> 'array'
     OR jsonb_array_length(p_items) = 0 THEN
    RETURN 0;
  END IF;
  IF jsonb_array_length(p_items) > 10000 THEN
    RAISE EXCEPTION 'too many items (max 10000)';
  END IF;

  -- أرضية العمر خادمية: لا قيمة من العميل تنزل تحت 90 يوماً.
  v_cut := now() - make_interval(days => GREATEST(coalesce(p_min_age_days, 90), 90));

  WITH req AS (
    SELECT DISTINCT it->>'entity' AS entity, it->>'id' AS id
    FROM jsonb_array_elements(p_items) it
    WHERE it->>'entity' IN ('records', 'appointments', 'xrays')
      AND coalesce(it->>'id', '') <> ''
  ),
  del AS (
    DELETE FROM public.sync_rows s
    USING req r
    WHERE s.user_id = v_uid
      AND s.entity  = r.entity
      AND s.id      = r.id
      AND s.updated_at < v_cut
    RETURNING s.entity
  )
  SELECT count(*)::int,
         jsonb_object_agg(entity, cnt)
    INTO v_n, v_ents
    FROM (SELECT entity, count(*) AS cnt FROM del GROUP BY entity) x;

  v_n := coalesce(v_n, 0);
  IF v_n > 0 THEN
    INSERT INTO public.archive_log(user_id, n_rows, entities)
    VALUES (v_uid, v_n, v_ents);
  END IF;
  RETURN v_n;
END $$;

-- درس 0015: المنحة الافتراضية على PUBLIC — تُسحب صراحةً ثم يُمنح المصرَّح.
REVOKE ALL ON FUNCTION public.archive_rows(jsonb, integer) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.archive_rows(jsonb, integer)
  TO authenticated, service_role;
